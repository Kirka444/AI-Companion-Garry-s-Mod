ENT.Type = "nextbot"
ENT.Base = "drgbase_nextbot_human"

if SERVER then
	local function GetMaster()
		local plys = player.GetAll()

		if #plys > 0 then
			return plys[1]
		end

		return nil
	end

	local HL2_VEHICLE_CLASSES = {
		["prop_vehicle_jeep"] = true,
		["prop_vehicle_airboat"] = true,
		["prop_vehicle_jeep_old"] = true,
		["prop_vehicle_driveable"] = true,
		["prop_vehicle_apc"] = true,
		["prop_vehicle_prisoner_pod"] = true,
	}

	local HELI_CFG = {
		FollowHeight = 130,
		EnemyHeight = 140,
		HoverThrottle = 0.5,
		MaxFollowSpeed = 240,
		MaxEnemySpeed = 400,
		FollowApproachDist = 350,
		EnemyApproachDist = 200,
		FollowDeadZone = 100,
		MaxPitch = 0.35,
		MaxRoll = 0.32,
		SoftAltLimit = 220,
		HardAltLimit = 900,
		MaxGroundAlt = 1200,
		DownForceMax = 8000,
	}

	local OBSTACLE_CHECK_DISTANCE = 350
	local OBSTACLE_NEAR_FRACTION = 0.5
	local DOOR_CLASSES = {
		["prop_door_rotating"] = true,
		["func_door"] = true,
	}

	local EXIT_OFFSET_BACK = 130
	local EXIT_OFFSET_SIDE = 130
	local EXIT_OFFSET_UP = 25
	local EXIT_HULL_MINS = Vector(-16, -16, 0)
	local EXIT_HULL_MAXS = Vector(16, 16, 72)

	local SEAT_EXIT_OFFSET_BACK = 110
	local SEAT_EXIT_OFFSET_SIDE = 110

	local PASSENGER_SEAT_SEARCH_RADIUS = 250
	local FREE_VEHICLE_SEARCH_RADIUS = 2000
	local PASSENGER_DETACH_DISTANCE = 600

	local VEHICLE_SEARCH_RADIUS = 700

	local HL2_FIRE_INPUT_DELAY = 0.05

	local STUCK_TRIGGER_DISTANCE = 130
	local STUCK_HARD_DISTANCE = 85
	local STUCK_LOW_SPEED = 60
	local STUCK_RAM_TRIGGER_DISTANCE = 110
	local STUCK_RAM_HARD_DISTANCE = 75
	local STUCK_RAM_LOW_SPEED = 85
	local STUCK_REVERSE_TIME = 0.9
	local STUCK_AVOID_TIME = 1.75
	local STUCK_RAM_REVERSE_TIME = 1.05
	local STUCK_RAM_AVOID_TIME = 1.35
	local STUCK_MAX_ATTEMPTS = 3
	local STUCK_RECOVERY_DELAY = 0.75
	local STUCK_GIVE_UP_DELAY = 1.5

	local GROUND_STOP_DISTANCE = 90
	local OBSTACLE_SLOW_DISTANCE = 300
	local OBSTACLE_STEER_DISTANCE = 260
	local OBSTACLE_RAM_STEER_DISTANCE = 220
	local REVERSE_STEER_THRESHOLD = -0.25
	local REVERSE_STEER_DISTANCE = 160
	local REVERSE_THROTTLE = -0.75
	local FULL_THROTTLE = 1.0
	local RAM_FULL_DISTANCE = 800
	local RAM_FAST_DISTANCE = 500
	local RAM_MEDIUM_DISTANCE = 180
	local RAM_SLOW_DISTANCE = 500

	local HELI_CIRCLE_RADIUS = 280
	local HELI_CIRCLE_SPEED = 0.35
	local HELI_PREDICTION_TIME = 0.4
	local HELI_FOLLOW_BEHIND = 180
	local HELI_FOLLOW_RECALC_DISTANCE = 15
	local HELI_YAW_THRESHOLD = -0.25
	local HELI_YAW_FULL = 0.8
	local HELI_YAW_SCALE = 1.5
	local HELI_PITCH_SCALE = 350
	local HELI_ROLL_SCALE = 700
	local HELI_ROLL_YAW_FACTOR = 0.25
	local HELI_HOVER_MIN = 0.15
	local HELI_HOVER_MAX = 0.85
	local HELI_ALT_DEAD_ZONE = 50
	local HELI_ALT_CLOSE = 60
	local HELI_ALT_FAR = 100
	local HELI_THROTTLE_SCALE = 0.0035
	local HELI_VEL_Z_SCALE = 0.005
	local HELI_VEL_Z_DEAD = 80
	local HELI_HOVER_ADJUST_RATE = 0.02
	local HELI_MIN_GROUND_CLEARANCE = 70
	local HELI_MIN_GROUND_THROTTLE_BOOST = 0.35
	local HELI_SMOOTH_RATE = 1.6
	local HELI_DOWN_FORCE_SCALE = 0.8
	local HELI_DOWN_FORCE_MIN_OVERSHOOT = 30
	local HELI_MASS_FALLBACK = 500
	local HELI_MASS_MIN = 1
	local HELI_MASS_MAX = 100000

	local function IsFinite(n)
		return type(n) == "number" and n == n and math.abs(n) ~= math.huge
	end

	local function ClampF(n, min, max, fallback)
		if not IsFinite(n) then
			return fallback or 0
		end

		return math.Clamp(n, min, max)
	end

	local function SafePos(ent)
		if not IsValid(ent) then
			return Vector(0, 0, 0)
		end

		return ent:GetPos() or Vector(0, 0, 0)
	end

	local function SafeForward(ent)
		if not IsValid(ent) then
			return Vector(1, 0, 0)
		end

		return ent:GetForward() or Vector(1, 0, 0)
	end

	local function SafeRight(ent)
		if not IsValid(ent) then
			return Vector(0, 1, 0)
		end

		return ent:GetRight() or Vector(0, 1, 0)
	end

	local function SafeUp(ent)
		if not IsValid(ent) then
			return Vector(0, 0, 1)
		end

		return ent:GetUp() or Vector(0, 0, 1)
	end

	local function SafeAngles(ent)
		if not IsValid(ent) then
			return Angle(0, 0, 0)
		end

		return ent:GetAngles() or Angle(0, 0, 0)
	end

	local function SafeVelocity(ent)
		if not IsValid(ent) then
			return Vector(0, 0, 0)
		end

		return ent:GetVelocity() or Vector(0, 0, 0)
	end

	local function SafeClass(ent)
		if not IsValid(ent) then
			return "invalid"
		end

		return ent:GetClass() or "invalid"
	end

	local function HasGlide()
		return rawget(_G, "Glide") ~= nil
	end

	local function IsGlideVehicle(ent)
		if not HasGlide() then
			return false
		end

		if not IsValid(ent) then
			return false
		end

		if ent.IsGlideVehicle == true then
			return true
		end

		if isfunction(ent.IsGlideVehicle) then
			local ok, res = pcall(function()
				return ent:IsGlideVehicle()
			end)

			if ok and res then
				return true
			end
		end

		return false
	end

	local function GetGlideRoot(ent)
		if not IsValid(ent) then
			return nil
		end

		if not HasGlide() then
			return nil
		end

		if IsGlideVehicle(ent) then
			return ent
		end

		local parent = ent:GetParent()

		if IsValid(parent) and IsGlideVehicle(parent) then
			return parent
		end

		if ent.vehicle and IsValid(ent.vehicle) and IsGlideVehicle(ent.vehicle) then
			return ent.vehicle
		end

		return nil
	end

	local function IsHL2Vehicle(ent)
		if not IsValid(ent) then
			return false
		end

		return HL2_VEHICLE_CLASSES[SafeClass(ent)] == true
	end

	local function GetVehicleRoot(ent)
		if not IsValid(ent) then
			return nil, nil
		end

		local glideRoot = GetGlideRoot(ent)

		if IsValid(glideRoot) then
			return glideRoot, "glide"
		end

		if IsHL2Vehicle(ent) then
			return ent, "hl2"
		end

		return nil, nil
	end

	local function GetGlideVehicleType(root)
		if not IsValid(root) then
			return "unknown"
		end

		if not HasGlide() then
			return "unknown"
		end

		if not Glide or not Glide.VEHICLE_TYPE then
			return "glide"
		end

		local vehType = root.VehicleType

		if vehType == Glide.VEHICLE_TYPE.HELICOPTER then
			return "helicopter"
		end

		if vehType == Glide.VEHICLE_TYPE.PLANE then
			return "plane"
		end

		if vehType == Glide.VEHICLE_TYPE.TANK then
			return "tank"
		end

		if vehType == Glide.VEHICLE_TYPE.BOAT then
			return "boat"
		end

		if vehType == Glide.VEHICLE_TYPE.MOTORCYCLE then
			return "motorcycle"
		end

		if vehType == Glide.VEHICLE_TYPE.CAR then
			return "car"
		end

		return "glide"
	end

	local function GetDriverSeat(root)
		if not IsValid(root) then
			return nil
		end

		if root.seats and IsValid(root.seats[1]) then
			return root.seats[1]
		end

		if IsHL2Vehicle(root) then
			return root
		end

		return nil
	end

	local function GetVehicleTypeString(root, mode)
		if mode == "hl2" then
			return SafeClass(root)
		end

		return GetGlideVehicleType(root)
	end

	local function FireHL2(veh, name, value)
		if not IsValid(veh) then
			return
		end

		pcall(function()
			if value == nil then
				veh:Fire(name)
			else
				veh:Fire(name, tostring(value), 0)
			end
		end)
	end

	local function ApplyGlideInputs(root, inputs)
		if not IsValid(root) then
			return
		end

		if not HasGlide() then
			return
		end

		if not isfunction(root.SetInputFloat) then
			return
		end

		pcall(function()
			if root.SetInputFloat then
				if inputs.throttle ~= nil then
					root:SetInputFloat(1, "throttle", ClampF(inputs.throttle, -1, 1, 0))
				end

				if inputs.accelerate ~= nil then
					root:SetInputFloat(1, "accelerate", ClampF(inputs.accelerate, 0, 1, 0))
				end

				if inputs.brake ~= nil then
					root:SetInputFloat(1, "brake", ClampF(inputs.brake, 0, 1, 0))
				end

				if inputs.steer ~= nil then
					root:SetInputFloat(1, "steer", ClampF(inputs.steer, -1, 1, 0))
				end

				if inputs.pitch ~= nil then
					root:SetInputFloat(1, "pitch", ClampF(inputs.pitch, -1, 1, 0))
				end

				if inputs.roll ~= nil then
					root:SetInputFloat(1, "roll", ClampF(inputs.roll, -1, 1, 0))
				end

				if inputs.yaw ~= nil then
					root:SetInputFloat(1, "yaw", ClampF(inputs.yaw, -1, 1, 0))
				end
			end

			if root.SetInputBool then
				if inputs.handbrake ~= nil then
					root:SetInputBool(1, "handbrake", inputs.handbrake == true)
				end

				if inputs.brakeBool ~= nil then
					root:SetInputBool(1, "brake", inputs.brakeBool == true)
				end

				if inputs.attack ~= nil then
					root:SetInputBool(1, "attack", inputs.attack == true)
				end

				if inputs.fire ~= nil then
					root:SetInputBool(1, "fire", inputs.fire == true)
				end
			end
		end)
	end

	local function EnsureEngineOn(bot)
		if not IsValid(bot) then
			return
		end

		if not bot._vehRoot or not IsValid(bot._vehRoot) then
			return
		end

		local root = bot._vehRoot
		local mode = bot._vehMode

		if mode == "hl2" then
			if not bot._vehEngineOn then
				FireHL2(root, "TurnOn")
				bot._vehEngineOn = true
			end
		elseif mode == "glide" then
			if not bot._vehEngineOn then
				pcall(function()
					if root.TurnOn then
						root:TurnOn()
					end

					if root.SetEngineState then
						root:SetEngineState(true)
					end
				end)

				bot._vehEngineOn = true
			end
		end
	end

	local function StopEngine(bot)
		if not IsValid(bot) then
			return
		end

		if not bot._vehRoot or not IsValid(bot._vehRoot) then
			return
		end

		local root = bot._vehRoot
		local mode = bot._vehMode

		if mode == "hl2" then
			FireHL2(root, "TurnOff")
		elseif mode == "glide" then
			pcall(function()
				if root.TurnOff then
					root:TurnOff()
				end

				if root.SetEngineState then
					root:SetEngineState(false)
				end
			end)
		end
	end

	local function CheckObstacle(root, dir, dist)
		if not IsValid(root) then
			return false, nil, dist or OBSTACLE_CHECK_DISTANCE
		end

		dist = dist or OBSTACLE_CHECK_DISTANCE

		local pos = SafePos(root)
		local forward = dir and Vector(dir.x, dir.y, 0) or Vector(SafeForward(root).x, SafeForward(root).y, 0)

		if forward:LengthSqr() < 0.001 then
			forward = Vector(1, 0, 0)
		end

		forward:Normalize()

		local tr = util.TraceHull({
			start = pos + Vector(0, 0, 40),
			endpos = pos + Vector(0, 0, 40) + forward * dist,
			mins = Vector(-40, -40, -20),
			maxs = Vector(40, 40, 25),
			filter = {root},
			mask = MASK_SOLID,
		})

		if tr.Hit and not tr.StartSolid and tr.Fraction < 1 then
			local ent = tr.Entity

			if IsValid(ent) then
				local class = SafeClass(ent)

				if not DOOR_CLASSES[class] then
					local hitDist = tr.Fraction * dist

					if hitDist < dist * OBSTACLE_NEAR_FRACTION then
						return true, tr.HitNormal, hitDist
					end

					return false, tr.HitNormal, hitDist
				end
			end
		end

		return false, nil, dist
	end

	local function GetAvoidanceDirection(root, targetDir, hitNormal)
		if not IsValid(root) or not hitNormal then
			return targetDir
		end

		local forward = Vector(SafeForward(root).x, SafeForward(root).y, 0)

		if forward:LengthSqr() < 0.001 then
			forward = Vector(1, 0, 0)
		end

		forward:Normalize()

		local right = Vector(SafeRight(root).x, SafeRight(root).y, 0)

		if right:LengthSqr() < 0.001 then
			right = Vector(0, 1, 0)
		end

		right:Normalize()

		local n = Vector(hitNormal.x, hitNormal.y, 0)

		if n:LengthSqr() < 0.001 then
			return targetDir
		end

		n:Normalize()

		local slide = targetDir - (targetDir:Dot(n) * n)
		slide.z = 0

		local away = -n * 0.5
		local result = slide + away

		if result:LengthSqr() < 0.01 then
			local rightDot = right:Dot(n)
			result = forward + right * (rightDot > 0 and -1 or 1)
		end

		result.z = 0

		if result:LengthSqr() < 0.01 then
			result = forward
		end

		result:Normalize()

		return result
	end

	local function GetTerrainHeight(pos)
		local tr = util.TraceLine({
			start = pos + Vector(0, 0, 1000),
			endpos = pos - Vector(0, 0, 1000),
			mask = MASK_SOLID,
		})

		if tr.Hit then
			return tr.HitPos.z
		end

		return pos.z - 1000
	end

	local function ActivityFromSequence(ent, seqName)
		if not IsValid(ent) or not isstring(seqName) then
			return nil
		end

		local ok, act = pcall(function()
			return ent:GetSequenceActivity(seqName)
		end)

		if ok and act and act > 0 then
			return act
		end

		local ok2, seq = pcall(function()
			return ent:LookupSequence(seqName)
		end)

		if ok2 and seq and seq >= 0 then
			local ok3, act2 = pcall(function()
				return ent:GetSequenceActivity(seq)
			end)

			if ok3 and act2 and act2 > 0 then
				return act2
			end
		end

		return nil
	end

	local function FindSafeExitPos(root)
		if not IsValid(root) then
			return Vector(0, 0, 0)
		end

		local base = SafePos(root)
		local fwd = SafeForward(root)
		local right = SafeRight(root)

		local candidates = {
			base - fwd * EXIT_OFFSET_BACK + Vector(0, 0, EXIT_OFFSET_UP),
			base + right * EXIT_OFFSET_SIDE + Vector(0, 0, EXIT_OFFSET_UP),
			base - right * EXIT_OFFSET_SIDE + Vector(0, 0, EXIT_OFFSET_UP),
			base + fwd * EXIT_OFFSET_BACK + Vector(0, 0, EXIT_OFFSET_UP),
			base + Vector(0, 0, 60),
		}

		for _, pos in ipairs(candidates) do
			local tr = util.TraceHull({
				start = pos + Vector(0, 0, 60),
				endpos = pos,
				mins = EXIT_HULL_MINS,
				maxs = EXIT_HULL_MAXS,
				mask = MASK_SOLID,
			})

			if not tr.Hit then
				return pos
			end
		end

		return base + Vector(0, 0, 40)
	end

	local function VehFix_CallVector(ent, method, ...)
		if not IsValid(ent) then
			return nil
		end

		if not isfunction(ent[method]) then
			return nil
		end

		local args = {...}

		local ok, vec = pcall(function()
			return ent[method](ent, unpack(args))
		end)

		if ok and isvector(vec) then
			return vec
		end

		return nil
	end

	local function VehFix_GetFieldVector(ent, names)
		if not IsValid(ent) then
			return nil
		end

		for _, k in ipairs(names) do
			local v = ent[k]

			if isvector(v) then
				return v
			end

			if istable(v) then
				if isvector(v[1]) then
					return v[1]
				end

				if isvector(v.Pos) then
					return v.Pos
				end

				if isvector(v.pos) then
					return v.pos
				end
			end
		end

		return nil
	end

	local function VehFix_GetAttachmentTransform(ent, names)
		if not IsValid(ent) then
			return nil, nil
		end

		for _, name in ipairs(names) do
			local ok, id = pcall(function()
				return ent:LookupAttachment(name)
			end)

			if ok and id and id > 0 then
				local ok2, att = pcall(function()
					return ent:GetAttachment(id)
				end)

				if ok2 and att and isvector(att.Pos) then
					return att.Pos, att.Ang
				end
			end
		end

		return nil, nil
	end

	local function VehFix_GetSavedViewPos(ent)
		if not IsValid(ent) then
			return nil
		end

		local ok, st = pcall(function()
			return ent:GetSaveTable()
		end)

		if not ok or not st then
			return nil
		end

		local views = st.m_ViewPositions

		if istable(views) then
			local m = views[1] or views[0]

			if m then
				local ok2, pos = pcall(function()
					return m:GetTranslation()
				end)

				if ok2 and isvector(pos) then
					return pos
				end

				if isvector(m) then
					return m
				end
			end
		end

		return nil
	end

	local function VehFix_GetDriverSeat(root)
		if not IsValid(root) then
			return nil
		end

		if IsValid(root.DriverSeat) then
			return root.DriverSeat
		end

		if istable(root.seats) then
			local best = nil
			local bestIndex = math.huge

			for i, seat in ipairs(root.seats) do
				if IsValid(seat) then
					local idx = tonumber(seat.GlideSeatIndex) or i

					if idx == 1 then
						return seat
					end

					if idx < bestIndex then
						bestIndex = idx
						best = seat
					end
				end
			end

			if best then
				return best
			end

			if IsValid(root.seats[1]) then
				return root.seats[1]
			end
		end

		if IsHL2Vehicle(root) then
			return root
		end

		return nil
	end

	local function VehFix_ChooseWorldPos(root, pos)
		if not IsValid(root) or not isvector(pos) then
			return pos
		end

		local candidates = {pos}

		local ok, localPos = pcall(function()
			return root:LocalToWorld(pos)
		end)

		if ok and isvector(localPos) then
			candidates[2] = localPos
		end

		local best = nil
		local bestScore = math.huge
		local rootPos = SafePos(root)

		for _, cand in ipairs(candidates) do
			if isvector(cand) then
				local d = cand:Distance(rootPos)

				if d >= 0 and d < 250 then
					local score = math.abs(d - 45)

					if score < bestScore then
						bestScore = score
						best = cand
					end
				end
			end
		end

		return best or pos
	end

	local function VehFix_GetSaveViewPosWorld(root)
		if not IsValid(root) then
			return nil
		end

		local ok, save = pcall(function()
			return root:GetSaveTable()
		end)

		if not ok or not save then
			return nil
		end

		local views = save.m_ViewPositions

		if not istable(views) then
			return nil
		end

		local m = views[1] or views[0]

		if not m then
			for _, v in pairs(views) do
				m = v

				break
			end
		end

		if not m then
			return nil
		end

		local ok2, p = pcall(function()
			if isvector(m) then
				return m
			end

			if isfunction(m.GetTranslation) then
				return m:GetTranslation()
			end

			if istable(m) and isvector(m.Pos) then
				return m.Pos
			end
		end)

		if ok2 and isvector(p) then
			return VehFix_ChooseWorldPos(root, p)
		end

		return nil
	end

	local function CalculateHL2LocalSeatTransform(root)
		if not IsValid(root) then
			return Vector(0, 0, 0), Angle(0, 0, 0)
		end

		local worldPos, worldAng = nil, nil

		local attachNames = {
			"vehicle_driver_eyes",
			"vehicle_driver",
			"driver_eyes",
			"driver",
		}

		for _, name in ipairs(attachNames) do
			local id = root:LookupAttachment(name)

			if id and id > 0 then
				local att = root:GetAttachment(id)

				if att and att.Pos then
					worldPos = att.Pos
					worldAng = att.Ang

					break
				end
			end
		end

		if not worldPos then
			local ok, save = pcall(function()
				return root:GetSaveTable()
			end)

			if ok and save and istable(save.m_ViewPositions) then
				local view = save.m_ViewPositions[1] or save.m_ViewPositions[0]

				if view then
					local vPos = nil

					if isfunction(view.GetTranslation) then
						vPos = view:GetTranslation()
					elseif isvector(view) then
						vPos = view
					elseif istable(view) and isvector(view.Pos) then
						vPos = view.Pos
					end

					if vPos then
						worldPos = root:LocalToWorld(vPos)
						worldAng = SafeAngles(root)
					end
				end
			end
		end

		if not worldPos then
			local center = root:OBBCenter()
			worldPos = root:LocalToWorld(center)
			worldAng = SafeAngles(root)
		end

		local localPos = root:WorldToLocal(worldPos)
		local localAng = root:WorldToLocalAngles(worldAng or Angle(0, 0, 0))

		localPos.z = localPos.z - 24
		localAng = Angle(0, localAng.y, 0)

		return localPos, localAng
	end

	local function VehFix_GetSitTransform(root, seat)
		local pos = nil
		local ang = nil
		local source = "none"

		if IsValid(root) and IsValid(seat) and seat.GlideSeatIndex then
			local v = VehFix_CallVector(root, "GetSeatPos", seat.GlideSeatIndex)

			if isvector(v) then
				pos = v
				source = "glide_api"
			end
		end

		if not pos then
			pos = VehFix_GetFieldVector(root, {
				"DriverPos",
				"DriverSeatPos",
				"DriverPosition",
				"SitPos",
				"PlayerPos",
			})

			if pos then
				source = "root_field"
			end
		end

		if not pos then
			pos = VehFix_GetFieldVector(seat, {
				"PlayerPos",
				"SitPos",
				"SeatPos",
				"ViewPos",
				"DriverPos",
			})

			if pos then
				source = "seat_field"
			end
		end

		if not pos and IsValid(root) and istable(root.SeatPositions) and isvector(root.SeatPositions[1]) then
			pos = root.SeatPositions[1]
			source = "root_seatpos"
		end

		if not pos and IsValid(seat) and istable(seat.SeatPositions) and isvector(seat.SeatPositions[1]) then
			pos = seat.SeatPositions[1]
			source = "seat_seatpos"
		end

		if not pos then
			local p, a = VehFix_GetAttachmentTransform(seat, {
				"vehicle_driver",
				"driver",
				"seat",
				"sit",
			})

			if p then
				pos = p
				ang = a
				source = "seat_attach"
			end
		end

		if not pos then
			local p, a = VehFix_GetAttachmentTransform(root, {
				"vehicle_driver",
				"driver",
				"seat",
				"sit",
			})

			if p then
				pos = p
				ang = a
				source = "root_attach"
			end
		end

		if not pos then
			pos = VehFix_GetSavedViewPos(seat)

			if pos then
				source = "seat_view"
			end
		end

		if not pos then
			pos = VehFix_GetSavedViewPos(root)

			if pos then
				source = "root_view"
			end
		end

		if not pos and IsValid(seat) then
			local ok, center = pcall(function()
				return seat:LocalToWorld(seat:OBBCenter())
			end)

			if ok and isvector(center) then
				pos = center
			else
				pos = seat:GetPos()
			end

			ang = seat:GetAngles()
			source = "seat_pos"
		end

		if not pos and IsValid(root) then
			local ok, center = pcall(function()
				return root:WorldSpaceCenter()
			end)

			if ok and isvector(center) then
				pos = center
			else
				pos = root:GetPos()
			end

			ang = root:GetAngles()
			source = "root_pos"
		end

		if not pos then
			pos = Vector(0, 0, 0)
		end

		if not ang then
			ang = Angle(0, 0, 0)
		end

		if IsValid(root) then
			local fwd = Vector(SafeForward(root).x, SafeForward(root).y, 0)

			if fwd:LengthSqr() > 0.001 then
				ang = Angle(0, fwd:Angle().y + SIT_YAW_OFFSET, 0)
			end
		end

		local down = SIT_DOWN_NORMAL

		if source == "seat_view" or source == "root_view" then
			down = SIT_DOWN_VIEW
		elseif source == "seat_attach" or source == "root_attach" then
			down = SIT_DOWN_ATTACH
		elseif source == "glide_api" then
			down = 10
		end

		if IsValid(root) then
			local fwd = SafeForward(root)
			local right = SafeRight(root)

			pos = pos - Vector(0, 0, down)
			pos = pos + fwd * SIT_BACK_OFFSET
			pos = pos + right * SIT_RIGHT_OFFSET
		else
			pos = pos - Vector(0, 0, down)
		end

		return pos, ang
	end

	local function VehFix_GetAimTargetPos(ent)
		if not IsValid(ent) then
			return Vector(0, 0, 0)
		end

		if ent.IsNPC and ent:IsNPC() then
			local names = {
				"ValveBiped.Bip01_Spine4",
				"ValveBiped.Bip01_Spine2",
				"ValveBiped.Bip01_Spine1",
			}

			for _, n in ipairs(names) do
				local ok, bone = pcall(function()
					return ent:LookupBone(n)
				end)

				if ok and bone then
					local ok2, bonePos = pcall(function()
						return ent:GetBonePosition(bone)
					end)

					if ok2 and bonePos and bonePos:LengthSqr() > 0.01 then
						return bonePos
					end
				end
			end
		end

		if ent.WorldSpaceCenter then
			local ok, pos = pcall(function()
				return ent:WorldSpaceCenter()
			end)

			if ok and pos then
				return pos
			end
		end

		return SafePos(ent)
	end

	local function Passenger_GetSeatDriver(seat)
		local driver = nil

		pcall(function()
			if IsValid(seat) and seat.GetDriver then
				driver = seat:GetDriver()
			end
		end)

		return driver
	end

	local function Passenger_IsSeatClass(ent)
		if not IsValid(ent) then
			return false
		end

		local class = SafeClass(ent)

		if class == "prop_vehicle_prisoner_pod" then
			return true
		end

		if class == "prop_vehicle_seat" then
			return true
		end

		if class:find("seat", 1, true) ~= nil then
			return true
		end

		return false
	end

	local function Passenger_GetMasterVehicleRoot(master)
		if not IsValid(master) then
			return nil
		end

		if not master.InVehicle or not master:InVehicle() then
			return nil
		end

		local veh = master:GetVehicle()

		if not IsValid(veh) then
			return nil
		end

		local r = GetVehicleRoot(veh)

		if IsValid(r) then
			return r
		end

		local parent = veh:GetParent()

		if IsValid(parent) then
			if IsGlideVehicle(parent) or IsHL2Vehicle(parent) then
				return parent
			end
		end

		return veh
	end

	local function Passenger_FindGlidePassengerSeat(root)
		if not IsValid(root) then
			return nil
		end

		if not istable(root.seats) then
			return nil
		end

		for i = 2, #root.seats do
			local seat = root.seats[i]

			if IsValid(seat) then
				local driver = Passenger_GetSeatDriver(seat)

				if not IsValid(driver) then
					return seat
				end
			end
		end

		return nil
	end

	local function Passenger_FindAttachedFreeSeat(root)
		if not IsValid(root) then
			return nil
		end

		if istable(root.seats) then
			for i = 2, #root.seats do
				local seat = root.seats[i]

				if IsValid(seat) then
					local driver = Passenger_GetSeatDriver(seat)

					if not IsValid(driver) then
						return seat
					end
				end
			end
		end

		local rootPos = SafePos(root)

		for _, ent in ipairs(ents.GetAll()) do
			if IsValid(ent) and ent ~= root and Passenger_IsSeatClass(ent) then
				local parent = ent:GetParent()
				local dist = SafePos(ent):Distance(rootPos)

				if parent == root or dist < PASSENGER_SEAT_SEARCH_RADIUS then
					local driver = Passenger_GetSeatDriver(ent)

					if not IsValid(driver) then
						return ent
					end
				end
			end
		end

		return nil
	end

	local function Passenger_FindSafeExitPos(root, seat)
		local base = SafePos(root)

		if IsValid(seat) then
			base = SafePos(seat)
		end

		local fwd = SafeForward(root)
		local right = SafeRight(root)

		local candidates = {
			base - fwd * SEAT_EXIT_OFFSET_BACK + Vector(0, 0, EXIT_OFFSET_UP),
			base + right * SEAT_EXIT_OFFSET_SIDE + Vector(0, 0, EXIT_OFFSET_UP),
			base - right * SEAT_EXIT_OFFSET_SIDE + Vector(0, 0, EXIT_OFFSET_UP),
			base + fwd * SEAT_EXIT_OFFSET_BACK + Vector(0, 0, EXIT_OFFSET_UP),
			base + Vector(0, 0, 50),
		}

		for _, pos in ipairs(candidates) do
			local tr = util.TraceHull({
				start = pos + Vector(0, 0, 60),
				endpos = pos,
				mins = EXIT_HULL_MINS,
				maxs = EXIT_HULL_MAXS,
				mask = MASK_SOLID,
			})

			if not tr.Hit then
				return pos
			end
		end

		return base + Vector(0, 0, 40)
	end

	local function Passenger_FindFreeVehicle(bot, excludeRoot, radius)
		radius = radius or FREE_VEHICLE_SEARCH_RADIUS

		if not IsValid(bot) then
			return nil
		end

		local botPos = bot:GetPos()
		local best = nil
		local bestDist = radius

		for _, ent in ipairs(ents.FindInSphere(botPos, radius)) do
			if IsValid(ent) then
				local root = GetVehicleRoot(ent)

				if IsValid(root) and root ~= excludeRoot then
					local seat = GetDriverSeat(root)

					if IsValid(seat) then
						local driver = Passenger_GetSeatDriver(seat)

						if not IsValid(driver) then
							local d = botPos:Distance(SafePos(root))

							if d < bestDist then
								bestDist = d
								best = root
							end
						end
					end
				end
			end
		end

		return best
	end

	function ENT:VehicleIsValid()
		if not IsValid(self) then
			return false
		end

		if not self._vehRoot then
			return false
		end

		if not IsValid(self._vehRoot) then
			return false
		end

		if self._vehMode == "glide" and self._vehSeat and not IsValid(self._vehSeat) then
			return false
		end

		return true
	end

	function ENT:VehicleIsPassenger()
		return self:VehicleIsValid() and self._vehPassenger == true
	end

	function ENT:VehicleIsHelicopter()
		if not self:VehicleIsValid() then
			return false
		end

		local root = self._vehRoot

		if not IsValid(root) then
			return false
		end

		if self._vehMode ~= "glide" then
			return false
		end

		local function hasHeli(value)
			if value == nil then
				return false
			end

			local s = tostring(value):lower()

			return s:find("heli", 1, true) ~= nil
		end

		if HasGlide() and Glide and Glide.VEHICLE_TYPE then
			if root.VehicleType == Glide.VEHICLE_TYPE.HELICOPTER then
				return true
			end
		end

		if hasHeli(root.VehicleType) then
			return true
		end

		if isfunction(root.GetVehicleType) then
			local ok, res = pcall(function()
				return root:GetVehicleType()
			end)

			if ok and hasHeli(res) then
				return true
			end
		end

		if isfunction(root.IsHelicopter) then
			local ok, res = pcall(function()
				return root:IsHelicopter()
			end)

			if ok and res then
				return true
			end
		end

		if hasHeli(SafeClass(root)) then
			return true
		end

		local okModel, model = pcall(function()
			return root:GetModel()
		end)

		if okModel and hasHeli(model) then
			return true
		end

		if hasHeli(root.PrintName) then
			return true
		end

		local okNW1, nwType = pcall(function()
			return root:GetNWString("GlideVehicleType", "")
		end)

		if okNW1 and hasHeli(nwType) then
			return true
		end

		local okNW2, nwName = pcall(function()
			return root:GetNWString("PrintName", "")
		end)

		if okNW2 and hasHeli(nwName) then
			return true
		end

		return false
	end

	function ENT:VehicleCanEnter(ent)
		if not IsValid(ent) then
			return false
		end

		local root, mode = GetVehicleRoot(ent)

		if not IsValid(root) then
			return false
		end

		local seat = VehFix_GetDriverSeat(root)

		if not IsValid(seat) then
			return false
		end

		if mode == "glide" then
			local driver = Passenger_GetSeatDriver(seat)

			if IsValid(driver) and driver ~= self then
				return false
			end
		end

		return true, root, mode, seat
	end

	function ENT:VehicleFindNearest(radius)
		radius = radius or VEHICLE_SEARCH_RADIUS

		local botPos = self:GetPos()
		local best = nil
		local bestDist = radius

		for _, ent in ipairs(ents.FindInSphere(botPos, radius)) do
			if IsValid(ent) then
				local root, mode = GetVehicleRoot(ent)

				if IsValid(root) and not self._vehUsed then
					local seat = GetDriverSeat(root)

					if IsValid(seat) then
						local driver = Passenger_GetSeatDriver(seat)

						if not IsValid(driver) or driver == self then
							local d = botPos:Distance(SafePos(root))

							if d < bestDist then
								bestDist = d
								best = root
							end
						end
					end
				end
			end
		end

		return best
	end

	function ENT:GetVehicleAnimationActivity()
		if not self:VehicleIsValid() then
			return nil
		end

		local vtype = self._vehType or "car"
		local seq = "drive_jeep"

		if vtype == "prop_vehicle_airboat" or vtype == "airboat" then
			seq = "drive_airboat"
		elseif vtype == "helicopter" then
			seq = "drive_airboat"
		end

		local act = ActivityFromSequence(self, seq)

		if act then
			return act
		end

		if vtype == "prop_vehicle_airboat" or vtype == "airboat" then
			return ACT_DRIVE_AIRBOAT or ACT_DRIVE or ACT_HL2MP_IDLE_PASSIVE
		elseif vtype == "helicopter" then
			return ACT_DRIVE or ACT_HL2MP_IDLE_PASSIVE
		end

		return ACT_DRIVE_JEEP or ACT_DRIVE or ACT_HL2MP_IDLE_PASSIVE
	end

	function ENT:VehiclePlayDriveAnimation()
		if not IsValid(self) then
			return
		end

		if not self._vehRoot or not IsValid(self._vehRoot) then
			return
		end

		local act = self:GetVehicleAnimationActivity()

		if not act then
			act = ACT_DRIVE
		end

		pcall(function()
			self:StartActivity(act)
		end)
	end

	function ENT:VehicleSaveAndStripWeapons()
		if self._vehWeaponsSaved then
			return
		end

		self._vehWeaponsSaved = true
		self._vehSavedWeapons = {}

		pcall(function()
			if self.GetWeapons then
				for _, w in ipairs(self:GetWeapons()) do
					if IsValid(w) then
						table.insert(self._vehSavedWeapons, w:GetClass())
					end
				end
			end
		end)

		if #self._vehSavedWeapons == 0 and istable(self.Weapons) then
			self._vehSavedWeapons = table.Copy(self.Weapons)
		end

		pcall(function()
			if self.HolsterWeapon then
				self:HolsterWeapon()
			end
		end)

		pcall(function()
			if self.StripWeapons then
				self:StripWeapons()
			end
		end)
	end

	function ENT:VehicleRestoreWeapons()
		if not self._vehWeaponsSaved then
			return
		end

		self._vehWeaponsSaved = nil

		pcall(function()
			if self.GetWeapons then
				for _, w in ipairs(self:GetWeapons()) do
					if IsValid(w) then
						w:Remove()
					end
				end
			end
		end)

		pcall(function()
			if self.StripWeapons then
				self:StripWeapons()
			end
		end)

		if istable(self._vehSavedWeapons) then
			for _, class in ipairs(self._vehSavedWeapons) do
				pcall(function()
					if not self:HasWeapon(class) then
						self:GiveWeapon(class)
					end
				end)
			end
		end

		self._vehSavedWeapons = nil

		timer.Simple(0.1, function()
			if not IsValid(self) then
				return
			end

			pcall(function()
				self:SwitchToPeaceful()
			end)

			pcall(function()
				self:SelectWeapon(self._idleWeaponClass or "weapon_physgun")
			end)
		end)
	end

	function ENT:VehicleAttachToSeat()
		if not self:VehicleIsValid() then
			return
		end

		local root = self._vehRoot

		if not IsValid(root) then
			self:SetParent(nil)
			self:VehicleExit()

			return
		end

		if self._vehMode == "glide" and self._vehSeat and not IsValid(self._vehSeat) then
			self:SetParent(nil)
			self:VehicleExit()

			return
		end

		if self._vehMode == "hl2" then
			local lPos, lAng = CalculateHL2LocalSeatTransform(root)

			pcall(function()
				if self.loco then
					self.loco:SetVelocity(Vector(0, 0, 0))
					self.loco:SetDesiredSpeed(0)
					self.loco:SetAcceleration(0)
					self.loco:SetDeceleration(0)
					pcall(function()
						self.loco:SetGravity(0)
					end)
				end
			end)

			if not IsValid(root) then
				self:SetParent(nil)

				return
			end

			self:SetParent(root)
			self:SetLocalPos(lPos)
			self:SetLocalAngles(lAng)

			self:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
			self:SetNotSolid(true)
		else
			-- === GLIDE: Следуем за сиденьем без Parent ===
			local seat = self._vehSeat
			local root = self._vehRoot

			if not IsValid(root) then
				return
			end

			-- НЕ используем Parent - просто следуем за позицией каждый тик
			if self:GetParent() then
				self:SetParent(nil)
			end

			-- Вычисляем целевую позицию
			local targetPos = nil
			local targetAng = nil

			if IsValid(seat) then
				-- Позиция сиденья - минимальный offset
				targetPos = seat:GetPos()
				targetPos.z = targetPos.z - 5 -- чуть ниже центра сиденья

				-- Угол: используем forward root (направление машины)
				local rootFwd = root:GetForward()
				targetAng = Angle(0, rootFwd:Angle().y, 0)
			else
				-- Fallback: позиция root
				targetPos = root:GetPos() + Vector(0, 0, 30)
				local rootFwd = root:GetForward()
				targetAng = Angle(0, rootFwd:Angle().y, 0)
			end

			-- Устанавливаем позицию напрямую
			self:SetPos(targetPos)
			self:SetAngles(targetAng)

			-- Полное отключение физики NextBot
			pcall(function()
				if self.loco then
					if self.loco.SetVelocity then
						self.loco:SetVelocity(Vector(0, 0, 0))
					end
					self.loco:SetDesiredSpeed(0)
					self.loco:SetAcceleration(0)
					self.loco:SetDeceleration(0)
				end
			end)

			-- Отключаем столкновения
			self:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
			self:SetNotSolid(true)
		end
	end
    hook.Add("Glide_CanRagdollPlayer", "drgbase_block_glide_ragdoll", function(ent, velocity, unragdollTime)
        if not IsValid(ent) then return end

        if ent.IsDrGNextBot then
            return false
        end

        if ent:GetClass() == "solo_companion_npc" then
            return false
        end
    end)
	hook.Add("PhysgunPickup", "gmod.one/solo-companion/physgun-block", function(ply, ent)
		if IsValid(ent) and ent.IsDrGNextBot and ent.VehicleIsValid and ent:VehicleIsValid() then
			return false
		end
	end)

	function ENT:VehicleEnter(ent)
		if not IsValid(self) then
			return false
		end

		if not self:Alive() then
			return false
		end

		if self:VehicleIsValid() then
			return true
		end

		local ok, root, mode, seat = self:VehicleCanEnter(ent)

		if not ok then
			self:ChatPrint("[AI] Не могу сесть в этот транспорт.")

			return false
		end

		self._vehRoot = root
		self._vehMode = mode
		self._vehSeat = seat
		self._vehPassenger = false
		self._vehType = GetVehicleTypeString(root, mode)
		self._vehEngineOn = false
		self._vehNextInput = 0
		self._vehNextFire = 0
		self._vehAnimPlayed = nil

		self._vehStuck = {
			phase = 0,
			reverseUntil = 0,
			avoidUntil = 0,
			side = 1,
			nextCheck = 0,
			attempts = 0,
			lastHitNormal = Vector(0, 0, 0),
		}

		self._vehHeli = {
			followPos = nil,
			lastOwnerPos = nil,
			circleAng = 0,
			p = 0,
			r = 0,
			y = 0,
			t = 0.5,
			hover = HELI_CFG.HoverThrottle,
			lastDesiredPos = nil,
			followTarget = nil,
			lastFollowOwnerPos = nil,
		}

		self._vehOldSolid = self:GetSolid()
		self._vehOldMoveType = self:GetMoveType()
		self._vehOldCollision = self:GetCollisionGroup()

		pcall(function()
			self:SetNotSolid(true)
		end)

		pcall(function()
			self:SetSolid(SOLID_NONE)
		end)

		pcall(function()
			self:SetMoveType(MOVETYPE_NONE)
		end)

		self:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)

		pcall(function()
			if self.loco and self.loco.Clear then
				self.loco:Clear()
			end
		end)

		pcall(function()
			if self.loco and self.loco.SetVelocity then
				self.loco:SetVelocity(Vector(0, 0, 0))
			end
		end)

		pcall(function()
			self.loco:SetDesiredSpeed(0)
			self.loco:SetAcceleration(0)
			self.loco:SetDeceleration(0)
		end)

		self:VehicleSaveAndStripWeapons()
		self:VehicleAttachToSeat()

		if self:VehicleIsHelicopter() then
			self._vehType = "helicopter"
		end

		self:ChatPrint("[AI] Сажусь в транспорт: " .. tostring(self._vehType))

		return true
	end

	function ENT:PassengerEnter(root, seat, mode)
		if not IsValid(self) then
			return false
		end

		if not self:Alive() then
			return false
		end

		if self:VehicleIsValid() then
			return true
		end

		if not IsValid(root) or not IsValid(seat) then
			return false
		end

		local driver = Passenger_GetSeatDriver(seat)

		if IsValid(driver) and driver ~= self then
			return false
		end

		self._vehRoot = root
		self._vehSeat = seat
		self._vehPassenger = true

		if mode == nil then
			if IsGlideVehicle(root) then
				mode = "glide"
			elseif IsHL2Vehicle(root) then
				mode = "hl2"
			else
				mode = "hl2"
			end
		end

		self._vehMode = mode
		self._vehType = GetVehicleTypeString(root, mode)

		self._vehEngineOn = false
		self._vehNextInput = 0
		self._vehNextFire = 0
		self._vehAnimPlayed = nil
		self._vehStuck = nil
		self._vehHeli = nil

		self._vehOldSolid = self:GetSolid()
		self._vehOldMoveType = self:GetMoveType()
		self._vehOldCollision = self:GetCollisionGroup()

		pcall(function()
			self:SetNotSolid(true)
		end)

		pcall(function()
			self:SetSolid(SOLID_NONE)
		end)

		pcall(function()
			self:SetMoveType(MOVETYPE_NONE)
		end)

		self:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)

		pcall(function()
			if self.loco and self.loco.Clear then
				self.loco:Clear()
			end
		end)

		pcall(function()
			if self.loco and self.loco.SetVelocity then
				self.loco:SetVelocity(Vector(0, 0, 0))
			end
		end)

		pcall(function()
			self.loco:SetDesiredSpeed(0)
			self.loco:SetAcceleration(0)
			self.loco:SetDeceleration(0)
		end)

		if self.VehicleSaveAndStripWeapons then
			self:VehicleSaveAndStripWeapons()
		end

		self:VehicleAttachToSeat()

		self:ChatPrint("[AI] Сажусь пассажиром в транспорт.")

		return true
	end

	function ENT:VehicleExit()
		if not IsValid(self) then
			return
		end

		if not self._vehRoot and not self._vehSeat then
			return
		end

		if self._isExitingVehicle then
			return
		end

		self._isExitingVehicle = true

		timer.Simple(0.5, function()
			if IsValid(self) then
				self._isExitingVehicle = false
			end
		end)

		local root = self._vehRoot
		local seat = self._vehSeat

		-- === FIX: Сохраняем мировую позицию ДО unparent ===
		local worldPos = self:GetPos()

		if not IsValid(root) or (self._vehMode == "glide" and not IsValid(seat)) then
			self:SetParent(nil)
			self:SetPos(worldPos)

			pcall(function()
				self:SetNotSolid(false)
			end)

			pcall(function()
				self:SetSolid(self._vehOldSolid or SOLID_BBOX)
			end)

			pcall(function()
				self:SetMoveType(self._vehOldMoveType or MOVETYPE_STEP)
			end)

			self:SetCollisionGroup(self._vehOldCollision or COLLISION_GROUP_PLAYER)

			-- === FIX: Полное восстановление loco ===
			pcall(function()
				if self.loco then
					self.loco:SetVelocity(Vector(0, 0, 0))
					self.loco:SetDesiredSpeed(0)
					self.loco:SetAcceleration(800)
					self.loco:SetDeceleration(800)
					if self.loco.SetGravity then
						self.loco:SetGravity(1)
					end
				end
			end)

			if self._vehWeaponsSaved then
				self:VehicleRestoreWeapons()
			end

			self._vehRoot = nil
			self._vehMode = nil
			self._vehSeat = nil
			self._vehType = nil
			self._vehPassenger = nil
			self._vehEngineOn = false
			self._vehNextInput = 0
			self._vehNextFire = 0
			self._vehStuck = nil
			self._vehHeli = nil
			self._vehAnimPlayed = nil
			self._vehOldSolid = nil
			self._vehOldMoveType = nil
			self._vehOldCollision = nil

			local master = GetMaster()

			if IsValid(master) then
				local pos = master:GetPos() + master:GetForward() * 50 + Vector(0, 0, 5)
				self:SetPos(pos)
			end

			self._aiDisabled = false
			self._myTarget = nil
			self._attackMode = false
			self._lastKnownPos = nil
			self:ClearTargetQueue()
			self:SwitchToPeaceful()

			if self.loco and self.loco.SetDesiredSpeed then
				self.loco:SetDesiredSpeed(0)
			end

			self:ChatPrint("[AI] Транспорт удалён! Восстанавливаюсь...")

			return
		end

		if not self:VehicleIsValid() and not self._vehRoot and not self._vehSeat then
			return
		end

		self:SetParent(nil)
		-- === FIX: Используем сохранённую мировую позицию ===
		self:SetPos(worldPos)

		if self._vehPassenger then
			local exitPos = Passenger_FindSafeExitPos(root, seat)
			self:SetPos(exitPos)

			pcall(function()
				self:SetNotSolid(false)
			end)

			pcall(function()
				self:SetSolid(self._vehOldSolid or SOLID_BBOX)
			end)

			pcall(function()
				self:SetMoveType(self._vehOldMoveType or MOVETYPE_STEP)
			end)

			self:SetCollisionGroup(self._vehOldCollision or COLLISION_GROUP_PLAYER)

			-- === FIX: Полное восстановление loco ===
			pcall(function()
				if self.loco then
					self.loco:SetVelocity(Vector(0, 0, 0))
					self.loco:SetDesiredSpeed(0)
					self.loco:SetAcceleration(800)
					self.loco:SetDeceleration(800)
					if self.loco.SetGravity then
						self.loco:SetGravity(1)
					end
				end
			end)

			if self.VehicleRestoreWeapons then
				self:VehicleRestoreWeapons()
			end

			self._vehRoot = nil
			self._vehMode = nil
			self._vehSeat = nil
			self._vehType = nil
			self._vehPassenger = nil
			self._vehEngineOn = false
			self._vehNextInput = 0
			self._vehNextFire = 0
			self._vehAnimPlayed = nil
			self._vehStuck = nil
			self._vehHeli = nil

			self._vehOldSolid = nil
			self._vehOldMoveType = nil
			self._vehOldCollision = nil

			self:ChatPrint("[AI] Вышел из пассажирского сиденья.")

			return
		end

		if self._vehMode == "hl2" then
			FireHL2(root, "Throttle", 0)
			FireHL2(root, "Steer", 0)
			FireHL2(root, "HandbrakeOn")
			StopEngine(self)
		elseif self._vehMode == "glide" then
			ApplyGlideInputs(root, {
				throttle = 0,
				accelerate = 0,
				brake = 1,
				steer = 0,
				pitch = 0,
				roll = 0,
				yaw = 0,
				handbrake = true,
				brakeBool = true,
				attack = false,
				fire = false,
			})

			StopEngine(self)
		end

		local exitPos = FindSafeExitPos(root)
		self:SetPos(exitPos)

		pcall(function()
			self:SetNotSolid(false)
		end)

		pcall(function()
			self:SetSolid(self._vehOldSolid or SOLID_BBOX)
		end)

		pcall(function()
			self:SetMoveType(self._vehOldMoveType or MOVETYPE_STEP)
		end)

		self:SetCollisionGroup(self._vehOldCollision or COLLISION_GROUP_PLAYER)

		-- === FIX: Полное восстановление loco ===
		pcall(function()
			if self.loco then
				self.loco:SetVelocity(Vector(0, 0, 0))
				self.loco:SetDesiredSpeed(0)
				self.loco:SetAcceleration(800)
				self.loco:SetDeceleration(800)
				if self.loco.SetGravity then
					self.loco:SetGravity(1)
				end
			end
		end)

		self:VehicleRestoreWeapons()

		self._vehRoot = nil
		self._vehMode = nil
		self._vehSeat = nil
		self._vehType = nil
		self._vehPassenger = nil
		self._vehEngineOn = false
		self._vehNextInput = 0
		self._vehNextFire = 0
		self._vehStuck = nil
		self._vehHeli = nil
		self._vehAnimPlayed = nil

		self._vehOldSolid = nil
		self._vehOldMoveType = nil
		self._vehOldCollision = nil

		self:ChatPrint("[AI] Вышел из транспорта.")
	end

	function ENT:VehicleStop()
		if not self:VehicleIsValid() then
			return
		end

		local root = self._vehRoot

		if self._vehMode == "hl2" then
			FireHL2(root, "Throttle", 0)
			FireHL2(root, "Steer", 0)
			FireHL2(root, "HandbrakeOn")
		elseif self._vehMode == "glide" then
			ApplyGlideInputs(root, {
				throttle = 0,
				accelerate = 0,
				brake = 1,
				steer = 0,
				handbrake = true,
				brakeBool = true,
				attack = false,
				fire = false,
			})
		end
	end

	function ENT:VehicleChooseAntiStuckSide(hitNormal)
		local root = self._vehRoot

		if not IsValid(root) then
			return 1
		end

		local right = Vector(SafeRight(root).x, SafeRight(root).y, 0)

		if right:LengthSqr() < 0.001 then
			right = Vector(0, 1, 0)
		end

		right:Normalize()

		if hitNormal then
			local n = Vector(hitNormal.x, hitNormal.y, 0)

			if n:LengthSqr() > 0.001 then
				n:Normalize()

				return right:Dot(n) >= 0 and -1 or 1
			end
		end

		return math.random() < 0.5 and 1 or -1
	end

	function ENT:VehicleUpdateAntiStuck(hasObstacle, hitNormal, obstacleDist, targetDist, isRamming, forwardDot)
		local root = self._vehRoot

		if not IsValid(root) then
			return 0, 0, false
		end

		local st = self._vehStuck

		if not st then
			return 0, 0, false
		end

		local now = CurTime()
		local speed = SafeVelocity(root):Length()

		obstacleDist = tonumber(obstacleDist) or 999999
		targetDist = tonumber(targetDist) or 999999
		forwardDot = tonumber(forwardDot) or 1

		local triggerDist = isRamming and STUCK_RAM_TRIGGER_DISTANCE or STUCK_TRIGGER_DISTANCE
		local hardDist = isRamming and STUCK_RAM_HARD_DISTANCE or STUCK_HARD_DISTANCE
		local lowSpeed = isRamming and STUCK_RAM_LOW_SPEED or STUCK_LOW_SPEED

		if st.phase == 1 then
			if now >= st.reverseUntil or ((not hasObstacle) and obstacleDist > 230 and targetDist > 230) then
				st.phase = 2
				st.avoidUntil = now + (isRamming and STUCK_RAM_AVOID_TIME or STUCK_AVOID_TIME)
				st.side = self:VehicleChooseAntiStuckSide(st.lastHitNormal or hitNormal)

				return 0.55, st.side, true
			end

			return -0.9, (st.side or 1) * 0.35, true
		end

		if st.phase == 2 then
			if now >= st.avoidUntil then
				st.phase = 0
				st.attempts = 0
				st.nextCheck = now + STUCK_RECOVERY_DELAY

				return 0, 0, false
			end

			if hasObstacle and obstacleDist < triggerDist * 0.75 then
				st.attempts = (st.attempts or 0) + 1

				if st.attempts > STUCK_MAX_ATTEMPTS then
					st.phase = 0
					st.attempts = 0
					st.nextCheck = now + STUCK_GIVE_UP_DELAY

					return 0, 0, false
				end

				st.phase = 1
				st.reverseUntil = now + STUCK_REVERSE_TIME + st.attempts * 0.2
				st.side = -(st.side or 1)
				st.lastHitNormal = hitNormal or Vector(0, 0, 0)

				return -0.95, st.side * 0.35, true
			end

			return 0.55, st.side or 1, true
		end

		if now < (st.nextCheck or 0) then
			return 0, 0, false
		end

		local needStuck = false

		if hasObstacle and obstacleDist < hardDist then
			needStuck = true
		elseif hasObstacle and obstacleDist < triggerDist and speed < lowSpeed then
			needStuck = true
		elseif isRamming and targetDist < 150 and speed < 75 then
			needStuck = true
		elseif forwardDot < -0.35 and targetDist > 180 and speed < 70 then
			needStuck = true
		end

		if needStuck then
			st.phase = 1
			st.attempts = 1
			st.reverseUntil = now + (isRamming and STUCK_RAM_REVERSE_TIME or STUCK_REVERSE_TIME)
			st.lastHitNormal = hitNormal or Vector(0, 0, 0)
			st.side = self:VehicleChooseAntiStuckSide(st.lastHitNormal)

			return -0.9, st.side * 0.35, true
		end

		return 0, 0, false
	end

	function ENT:VehicleGroundInputs(targetPos, ramTarget)
		if not self:VehicleIsValid() then
			return
		end

		if not targetPos then
			return
		end

		local root = self._vehRoot

		if not IsValid(root) then
			return
		end

		local vehPos = SafePos(root)
		local toTarget = Vector(targetPos.x - vehPos.x, targetPos.y - vehPos.y, 0)
		local dist = toTarget:Length()

		EnsureEngineOn(self)

		if dist < GROUND_STOP_DISTANCE and not IsValid(ramTarget) then
			if self._vehMode == "hl2" then
				FireHL2(root, "Throttle", 0)
				FireHL2(root, "Steer", 0)
				FireHL2(root, "HandbrakeOn")
			else
				ApplyGlideInputs(root, {
					throttle = 0,
					accelerate = 0,
					brake = 1,
					steer = 0,
					handbrake = true,
					brakeBool = true,
				})
			end

			return
		end

		if dist > 1 then
			toTarget:Normalize()
		else
			toTarget = Vector(SafeForward(root).x, SafeForward(root).y, 0)
		end

		local forward = Vector(SafeForward(root).x, SafeForward(root).y, 0)

		if forward:LengthSqr() < 0.001 then
			forward = Vector(1, 0, 0)
		end

		forward:Normalize()

		local right = Vector(SafeRight(root).x, SafeRight(root).y, 0)

		if right:LengthSqr() < 0.001 then
			right = Vector(0, 1, 0)
		end

		right:Normalize()

		local hasObstacle, hitNormal, obstacleDist = CheckObstacle(root, forward, 480)
		local dir = toTarget

		if hasObstacle and obstacleDist < OBSTACLE_SLOW_DISTANCE then
			dir = GetAvoidanceDirection(root, dir, hitNormal)
		end

		local forwardDot = forward:Dot(dir)
		local rightDot = right:Dot(dir)

		local asThrottle, asSteer, asActive = self:VehicleUpdateAntiStuck(
			hasObstacle,
			hitNormal,
			obstacleDist,
			dist,
			IsValid(ramTarget),
			forwardDot
		)

		local throttle = 0
		local steer = 0

		if asActive then
			throttle = asThrottle
			steer = asSteer
		elseif IsValid(ramTarget) then
			if forwardDot < REVERSE_STEER_THRESHOLD and dist > REVERSE_STEER_DISTANCE then
				throttle = REVERSE_THROTTLE
				steer = rightDot > 0 and -1 or 1
			else
				throttle = FULL_THROTTLE

				if forwardDot > 0.1 then
					steer = rightDot * 1.7
				else
					steer = rightDot > 0 and 1 or -1
				end

				if hasObstacle and obstacleDist < OBSTACLE_RAM_STEER_DISTANCE then
					steer = steer * 1.35
				end
			end
		else
			if dist > RAM_FULL_DISTANCE then
				throttle = FULL_THROTTLE
			elseif dist > RAM_FAST_DISTANCE then
				throttle = 0.65
			elseif dist > RAM_MEDIUM_DISTANCE then
				throttle = 0.4
			else
				throttle = 0.2
			end

			if hasObstacle then
				throttle = throttle * math.Clamp((obstacleDist - 120) / 320, 0.2, 0.85)
			end

			if forwardDot < -0.45 and dist > 260 then
				throttle = -0.4
			end

			if forwardDot > 0.1 then
				steer = rightDot * 1.35
			else
				steer = rightDot > 0 and 1 or -1
			end

			if hasObstacle and obstacleDist < OBSTACLE_STEER_DISTANCE then
				steer = steer * 1.5
			end
		end

		steer = ClampF(steer, -1, 1, 0)
		throttle = ClampF(throttle, -1, 1, 0)

		if self._vehMode == "hl2" then
			if CurTime() >= (self._vehNextInput or 0) then
				FireHL2(root, "Throttle", throttle)
				FireHL2(root, "Steer", steer)
				FireHL2(root, "HandbrakeOff")
				self._vehNextInput = CurTime() + HL2_FIRE_INPUT_DELAY
			end
		elseif self._vehMode == "glide" then
			ApplyGlideInputs(root, {
				throttle = throttle,
				accelerate = math.max(0, throttle),
				brake = math.max(0, -throttle),
				steer = steer,
				handbrake = false,
				brakeBool = false,
				attack = IsValid(ramTarget),
				fire = IsValid(ramTarget),
			})
		end
	end

	function ENT:VehicleApplyHeliDownForce(root, target, desiredPos)
		if not IsValid(root) or not IsValid(target) or not desiredPos then
			return
		end

		if not HasGlide() then
			return
		end

		local vehPos = SafePos(root)

		local heightAboveTarget = vehPos.z - desiredPos.z

		if heightAboveTarget < HELI_CFG.SoftAltLimit then
			return
		end

		local phys = nil

		pcall(function()
			phys = root:GetPhysicsObject()
		end)

		if not phys then
			return
		end

		local ok, valid = pcall(function()
			return phys:IsValid()
		end)

		if not ok or not valid then
			return
		end

		local mass = HELI_MASS_FALLBACK

		pcall(function()
			mass = phys:GetMass()
		end)

		mass = ClampF(mass, HELI_MASS_MIN, HELI_MASS_MAX, HELI_MASS_FALLBACK)

		local up = SafeUp(root)
		local overshoot = heightAboveTarget - HELI_CFG.SoftAltLimit

		if overshoot < HELI_DOWN_FORCE_MIN_OVERSHOOT then
			return
		end

		local force = math.min(overshoot * mass * HELI_DOWN_FORCE_SCALE, HELI_CFG.DownForceMax)

		pcall(function()
			phys:ApplyForceCenter((-up) * force)
		end)
	end

	function ENT:VehicleHeliCalculateInputs(target, isEnemy)
		local root = self._vehRoot

		local empty = {
			throttle = HELI_CFG.HoverThrottle,
			pitch = 0,
			roll = 0,
			yaw = 0,
		}

		if not IsValid(root) or not IsValid(target) then
			return empty
		end

		if self._vehMode ~= "glide" then
			return empty
		end

		local ap = self._vehHeli

		if not ap then
			ap = {}
			self._vehHeli = ap
		end

		ap.hover = ClampF(ap.hover or HELI_CFG.HoverThrottle, HELI_HOVER_MIN, HELI_HOVER_MAX, HELI_CFG.HoverThrottle)

		local dt = math.Clamp(FrameTime(), 0.001, 0.05)

		local vehPos = SafePos(root)
		local vehVel = SafeVelocity(root)

		local forward = Vector(SafeForward(root).x, SafeForward(root).y, 0)

		if forward:LengthSqr() < 0.001 then
			forward = Vector(1, 0, 0)
		end

		forward:Normalize()

		local right = Vector(SafeRight(root).x, SafeRight(root).y, 0)

		if right:LengthSqr() < 0.001 then
			right = Vector(0, 1, 0)
		end

		right:Normalize()

		local targetPos = VehFix_GetAimTargetPos(target)
		local targetVel = SafeVelocity(target)
		targetVel.z = 0

		local predictedPos = targetPos + targetVel * HELI_PREDICTION_TIME
		local desiredPos

		if isEnemy then
			ap.circleAng = (ap.circleAng or 0) + dt * HELI_CIRCLE_SPEED

			local tFw = Vector(SafeForward(target).x, SafeForward(target).y, 0)

			if tFw:LengthSqr() < 0.001 then
				tFw = Vector(1, 0, 0)
			end

			tFw:Normalize()

			local tRt = Vector(SafeRight(target).x, SafeRight(target).y, 0)

			if tRt:LengthSqr() < 0.001 then
				tRt = Vector(0, 1, 0)
			end

			tRt:Normalize()

			local offset = tRt * math.cos(ap.circleAng) * HELI_CIRCLE_RADIUS
				+ tFw * math.sin(ap.circleAng) * HELI_CIRCLE_RADIUS * 0.3

			desiredPos = predictedPos + offset
			desiredPos.z = targetPos.z + HELI_CFG.EnemyHeight
		else
			if ap.followTarget ~= target then
				ap.followTarget = target
				ap.followPos = nil
				ap.lastFollowOwnerPos = nil
			end

			local moved = ap.lastFollowOwnerPos and targetPos:Distance(ap.lastFollowOwnerPos) or 999999

			if not ap.followPos or moved > HELI_FOLLOW_RECALC_DISTANCE then
				local dir

				if targetVel:Length() > 15 then
					dir = targetVel:GetNormalized()
				else
					dir = Vector(SafeForward(target).x, SafeForward(target).y, 0)
				end

				dir.z = 0

				if dir:LengthSqr() < 0.001 then
					dir = Vector(1, 0, 0)
				end

				dir:Normalize()

				ap.followPos = predictedPos - dir * HELI_FOLLOW_BEHIND
				ap.followPos.z = targetPos.z + HELI_CFG.FollowHeight
				ap.lastFollowOwnerPos = targetPos
			end

			desiredPos = ap.followPos
		end

		if not desiredPos then
			desiredPos = targetPos + Vector(0, 0, HELI_CFG.FollowHeight)
		end

		ap.lastDesiredPos = desiredPos

		local toDesired = desiredPos - vehPos
		local horiz = Vector(toDesired.x, toDesired.y, 0)
		local distXY = horiz:Length()

		local dirH = forward

		if distXY > 1 then
			dirH = horiz:GetNormalized()
		end

		if distXY < HELI_CFG.FollowDeadZone and not isEnemy then
			return {
				throttle = ap.hover,
				pitch = 0,
				roll = 0,
				yaw = 0,
			}
		end

		local maxSpeed = isEnemy and HELI_CFG.MaxEnemySpeed or HELI_CFG.MaxFollowSpeed
		local approachDist = isEnemy and HELI_CFG.EnemyApproachDist or HELI_CFG.FollowApproachDist

		local desiredSpeed = maxSpeed

		if distXY < approachDist then
			desiredSpeed = maxSpeed * (distXY / approachDist)
		end

		local velH = Vector(vehVel.x, vehVel.y, 0)
		local desiredVel = dirH * desiredSpeed
		local velError = desiredVel - velH

		local fwdErr = velError:Dot(forward)
		local rightErr = velError:Dot(right)

		local yawInput = 0

		if distXY > 50 then
			local dotF = forward:Dot(dirH)
			local dotR = right:Dot(dirH)

			if dotF < HELI_YAW_THRESHOLD then
				yawInput = dotR >= 0 and HELI_YAW_FULL or -HELI_YAW_FULL
			else
				yawInput = math.Clamp(dotR * HELI_YAW_SCALE, -HELI_YAW_FULL, HELI_YAW_FULL)
			end
		end

		local pitchInput = math.Clamp(fwdErr / HELI_PITCH_SCALE, -HELI_CFG.MaxPitch, HELI_CFG.MaxPitch)
		local rollInput = math.Clamp(yawInput * HELI_ROLL_YAW_FACTOR + rightErr / HELI_ROLL_SCALE, -HELI_CFG.MaxRoll, HELI_CFG.MaxRoll)

		if math.abs(yawInput) > 0.5 then
			pitchInput = pitchInput * 0.3
		end

		local heightError = desiredPos.z - vehPos.z

		if math.abs(heightError) < HELI_ALT_DEAD_ZONE then
			if vehVel.z > HELI_VEL_Z_DEAD then
				ap.hover = ap.hover - dt * HELI_HOVER_ADJUST_RATE
			elseif vehVel.z < -HELI_VEL_Z_DEAD then
				ap.hover = ap.hover + dt * HELI_HOVER_ADJUST_RATE
			end

			ap.hover = ClampF(ap.hover, HELI_HOVER_MIN, HELI_HOVER_MAX, HELI_CFG.HoverThrottle)
		end

		local throttleInput = ap.hover + heightError * HELI_THROTTLE_SCALE - vehVel.z * HELI_VEL_Z_SCALE

		if math.abs(heightError) < 20 then
			throttleInput = ap.hover
		elseif heightError > HELI_ALT_CLOSE then
			throttleInput = math.max(throttleInput, ap.hover + 0.15)
		elseif heightError < -HELI_ALT_CLOSE then
			throttleInput = math.min(throttleInput, ap.hover - 0.15)
		end

		if heightError > HELI_ALT_FAR then
			throttleInput = math.min(throttleInput, ap.hover + 0.25)
		elseif heightError < -HELI_ALT_FAR then
			throttleInput = math.max(throttleInput, ap.hover - 0.25)
		end

		local groundZ = GetTerrainHeight(vehPos)
		local heightAboveGround = vehPos.z - groundZ
		local heightAboveTarget = vehPos.z - targetPos.z

		if heightAboveTarget > HELI_CFG.SoftAltLimit then
			throttleInput = math.min(throttleInput, ap.hover)
		end

		if heightAboveTarget > HELI_CFG.HardAltLimit or heightAboveGround > HELI_CFG.MaxGroundAlt then
			throttleInput = math.min(throttleInput, ap.hover - 0.25)
			pitchInput = math.Clamp(pitchInput, -0.15, 0.15)
			rollInput = math.Clamp(rollInput, -0.15, 0.15)
		end

		if heightAboveGround < HELI_MIN_GROUND_CLEARANCE then
			throttleInput = math.max(throttleInput, ap.hover + HELI_MIN_GROUND_THROTTLE_BOOST)
			pitchInput = math.Clamp(pitchInput, -0.12, 0.12)
			rollInput = math.Clamp(rollInput, -0.12, 0.12)
		end

		throttleInput = ClampF(throttleInput, -1, 1, ap.hover)

		local smooth = math.Clamp(dt * HELI_SMOOTH_RATE, 0, 1)

		ap.p = (ap.p or 0) + (pitchInput - (ap.p or 0)) * smooth
		ap.r = (ap.r or 0) + (rollInput - (ap.r or 0)) * smooth
		ap.y = (ap.y or 0) + (yawInput - (ap.y or 0)) * smooth
		ap.t = (ap.t or ap.hover) + (throttleInput - (ap.t or ap.hover)) * smooth

		ap.t = ClampF(ap.t, -1, 1, ap.hover)
		ap.p = ClampF(ap.p, -1, 1, 0)
		ap.r = ClampF(ap.r, -1, 1, 0)
		ap.y = ClampF(ap.y, -1, 1, 0)

		return {
			throttle = ap.t,
			pitch = ap.p,
			roll = ap.r,
			yaw = ap.y,
		}
	end

	function ENT:VehicleHeliInputs(target, isEnemy)
		if not self:VehicleIsValid() then
			return
		end

		if not IsValid(target) then
			return
		end

		local root = self._vehRoot

		if not IsValid(root) then
			return
		end

		local inputs = self:VehicleHeliCalculateInputs(target, isEnemy)

		if inputs then
			ApplyGlideInputs(root, inputs)
		end

		local ap = self._vehHeli

		if ap and ap.lastDesiredPos then
			self:VehicleApplyHeliDownForce(root, target, ap.lastDesiredPos)
		end
	end

	function ENT:PassengerThink()
		if not self:Alive() then
			self:VehicleExit()

			return false
		end

		local root = self._vehRoot
		local seat = self._vehSeat

		if not IsValid(root) or not IsValid(seat) then
			self:VehicleExit()

			return false
		end

		local master = GetMaster()

		if IsValid(master) then
			if not master:InVehicle() then
				self:VehicleExit()

				return false
			end

			local masterRoot = Passenger_GetMasterVehicleRoot(master)

			if not IsValid(masterRoot) or masterRoot ~= root then
				self:VehicleExit()

				return false
			end
		end

		local driver = Passenger_GetSeatDriver(seat)

		if IsValid(driver) and driver ~= self then
			self:VehicleExit()

			return false
		end

		if SafePos(seat):Distance(SafePos(root)) > PASSENGER_DETACH_DISTANCE then
			self:VehicleExit()

			return false
		end

		self:VehicleAttachToSeat()

		return true
	end

	function ENT:TryPassengerBoard(master)
		if not IsValid(self) then
			return false
		end

		if not self:Alive() then
			return false
		end

		if self:VehicleIsValid() then
			return true
		end

		if not IsValid(master) then
			return false
		end

		if not master:InVehicle() then
			return false
		end

		local plyVeh = master:GetVehicle()

		if not IsValid(plyVeh) then
			return false
		end

		local plyRoot = Passenger_GetMasterVehicleRoot(master)

		if not IsValid(plyRoot) then
			return false
		end

		local plyMode = nil

		local r, m = GetVehicleRoot(plyVeh)

		if IsValid(r) then
			plyMode = m
		end

		if not plyMode then
			if IsGlideVehicle(plyRoot) then
				plyMode = "glide"
			elseif IsHL2Vehicle(plyRoot) then
				plyMode = "hl2"
			else
				plyMode = "hl2"
			end
		end

		local vehDriver = Passenger_GetSeatDriver(plyVeh)

		if not IsValid(vehDriver) then
			vehDriver = Passenger_GetSeatDriver(plyRoot)
		end

		if IsValid(vehDriver) and vehDriver ~= master then
			return false
		end

		if plyMode == "glide" then
			local glideSeat = Passenger_FindGlidePassengerSeat(plyRoot)

			if IsValid(glideSeat) then
				return self:PassengerEnter(plyRoot, glideSeat, "glide")
			end
		end

		local freeSeat = Passenger_FindAttachedFreeSeat(plyRoot)

		if IsValid(freeSeat) then
			return self:PassengerEnter(plyRoot, freeSeat, plyMode)
		end

		local freeVeh = Passenger_FindFreeVehicle(self, plyRoot, 2500)

		if IsValid(freeVeh) then
			if self:VehicleEnter(freeVeh) then
				self:ChatPrint("[AI] Пассажирского места нет, беру свободный транспорт.")

				return true
			end
		end

		self:ChatPrint("[AI] Нет свободного сиденья или транспорта рядом.")

		return false
	end

	function ENT:IsTargetAliveVehicle(ent)
		if not IsValid(ent) then
			return false
		end

		if ent:IsPlayer() then
			return ent:Alive()
		end

		if ent:IsNPC() or ent:IsNextBot() then
			return ent:Alive() and ent:Health() > 0
		end

		return ent:Health() > 0
	end

	function ENT:VehicleThink()
		if not IsValid(self) then
			return false
		end

		if not self._vehRoot then
			return false
		end

		if not self:Alive() then
			self:VehicleExit()

			return false
		end

		local root = self._vehRoot

		-- === FIX: Убраны агрессивные проверки - они дублируются в CustomThink ===
		-- Теперь grace period обрабатывается в одном месте (solo_companion_npc.lua)
		if not IsValid(root) then
			-- Не вызываем VehicleExit сразу - даём время на восстановление
			return false
		end

		if self._vehMode == "glide" and self._vehSeat and not IsValid(self._vehSeat) then
			-- Для Glide тоже даём время
			return false
		end

		if self._vehPassenger then
			return self:PassengerThink()
		end

		if self:VehicleIsHelicopter() then
			self._vehType = "helicopter"
		end

		-- === GLIDE: Следуем за сиденьем каждый тик ===
		-- Для Glide НУЖНО вызывать каждый тик чтобы обновлять позицию
		self:VehicleAttachToSeat()
		EnsureEngineOn(self)

		local master = GetMaster()
		local enemy = self._myTarget

		if IsValid(enemy) and not self:IsTargetAliveVehicle(enemy) then
			enemy = nil
			self._myTarget = nil
		end

		local targetEnt = IsValid(enemy) and enemy or master
		local isEnemy = IsValid(enemy)

		if not IsValid(targetEnt) then
			self:VehicleStop()

			return true
		end

		if self:VehicleIsHelicopter() or self._vehType == "helicopter" then
			self:VehicleHeliInputs(targetEnt, isEnemy)

			return true
		end

		local targetPos

		if isEnemy then
			targetPos = targetEnt:WorldSpaceCenter()
		else
			targetPos = SafePos(master)
		end

		self:VehicleGroundInputs(targetPos, isEnemy and enemy or nil)

		if isEnemy and self._vehMode == "hl2" then
			local dist = SafePos(root):Distance(enemy:GetPos())

			if dist < 2500 and self:Visible(enemy) then
				if CurTime() >= (self._vehNextFire or 0) then
					FireHL2(root, "Action")
					self._vehNextFire = CurTime() + 0.2
				end
			end
		end

		return true
	end

	function ENT:ShouldCollide(ent)
		if self:VehicleIsValid() then
			if not IsValid(ent) then
				return false
			end

			if ent == self._vehRoot then
				return false
			end

			if ent == self._vehSeat then
				return false
			end

			local parent = ent:GetParent()

			if IsValid(parent) then
				if parent == self._vehRoot then
					return false
				end

				if parent == self._vehSeat then
					return false
				end
			end

			if IsGlideVehicle(ent) then
				return false
			end

			if IsHL2Vehicle(ent) then
				return false
			end
		end

		return true
	end

	do
		local oldOnUpdateAnimation = ENT.OnUpdateAnimation

		function ENT:OnUpdateAnimation()
			if self:VehicleIsValid() then
				local act = self:GetVehicleAnimationActivity()

				if act then
					return act, 1
				end
			end

			if oldOnUpdateAnimation then
				return oldOnUpdateAnimation(self)
			end
		end
	end

	concommand.Add("ai_solo_enter_passenger", function(ply)
		if not IsValid(ply) or not ply:IsPlayer() then
			return
		end

		local master = GetMaster()

		if not IsValid(master) then
			return
		end

		local npc = nil

		for _, ent in ipairs(ents.FindByClass("solo_companion_npc")) do
			if IsValid(ent) then
				npc = ent

				break
			end
		end

		if not IsValid(npc) then
			ply:ChatPrint("[AI] Companion not found!")

			return
		end

		if npc:VehicleIsValid() then
			ply:ChatPrint("[AI] Companion is already in a vehicle!")

			return
		end

		if npc:TryPassengerBoard(master) then
			ply:ChatPrint("[AI] Companion boarded!")
		else
			ply:ChatPrint("[AI] Companion could not board.")
		end
	end)

	hook.Add("PlayerEnteredVehicle", "gmod.one/solo-companion/auto-passenger", function(ply, veh, role)
		if not IsValid(ply) then
			return
		end

		if ply ~= GetMaster() then
			return
		end

		timer.Simple(0.3, function()
			if not IsValid(ply) then
				return
			end

			if not ply:InVehicle() then
				return
			end

			local mVeh = ply:GetVehicle()

			if not IsValid(mVeh) then
				return
			end

			local drv = Passenger_GetSeatDriver(mVeh)

			if not IsValid(drv) then
				local tmpRoot = Passenger_GetMasterVehicleRoot(ply)

				if IsValid(tmpRoot) then
					drv = Passenger_GetSeatDriver(tmpRoot)
				end
			end

			if IsValid(drv) and drv ~= ply then
				return
			end

			local masterRoot = Passenger_GetMasterVehicleRoot(ply)

			for _, npc in ipairs(ents.FindByClass("solo_companion_npc")) do
				if IsValid(npc) then
					if npc:VehicleIsValid() and npc._vehPassenger and npc._vehRoot ~= masterRoot then
						npc:VehicleExit()
					end

					if not npc:VehicleIsValid() then
						npc:TryPassengerBoard(ply)
					end
				end
			end
		end)
	end)

	hook.Add("PlayerLeaveVehicle", "gmod.one/solo-companion/auto-passenger-exit", function(ply, veh)
		if not IsValid(ply) then
			return
		end

		if ply ~= GetMaster() then
			return
		end

		timer.Simple(0.35, function()
			if not IsValid(ply) then
				return
			end

			if ply:InVehicle() then
				return
			end

			for _, npc in ipairs(ents.FindByClass("solo_companion_npc")) do
				if IsValid(npc) and npc:VehicleIsValid() then
					npc:VehicleExit()
				end
			end
		end)
	end)

	hook.Add("EntityRemoved", "gmod.one/solo-companion/vehicle-safety", function(ent)
		if not IsValid(ent) then
			return
		end

		if not ent.IsDrGNextBot then
			return
		end

		if not ent.VehicleIsValid then
			return
		end

		if ent._vehRoot == ent or ent._vehSeat == ent then
			pcall(function()
				ent._vehRoot = nil
				ent._vehSeat = nil
				ent._vehMode = nil
				ent._vehPassenger = nil
			end)
		end
	end)

	hook.Add("EntityRemoved", "gmod.one/solo-companion/vehicle-deleted", function(ent)
		-- === FIX: Предотвращаем двойной респавн ===
		if ent._soloNPCRespawnTriggered then
			return
		end
		ent._soloNPCRespawnTriggered = true

		for _, npc in ipairs(ents.FindByClass("solo_companion_npc")) do
			if IsValid(npc) and not npc._isBeingRespawned then
				if npc._vehRoot == ent or npc._vehSeat == ent then
					npc._isBeingRespawned = true

					-- === СОХРАНЯЕМ ВСЁ СОСТОЯНИЕ ===
					local saveData = {
						pos = npc:GetPos(),
						model = npc._customModel or "models/player/urban.mdl",
						nick = npc._customNick or "Companion",
						combatWeapon = npc._combatWeaponClass or "weapon_smg1",
						idleWeapon = npc._idleWeaponClass or "weapon_physgun",
						healEnabled = npc._healEnabled,
						healThreshold = npc._healThreshold,
						defenderMode = npc._defenderMode,
						stealthMode = npc._stealthMode,
						pacifistMode = npc._pacifistMode,
						aggressiveMode = npc._aggressiveMode,
					}

					-- === УДАЛЯЕМ СТАРОГО БОТА ===
					timer.Remove("gmod.one/solo-companion/color-sync-" .. npc:EntIndex())
					timer.Remove("gmod.one/solo-companion/aggro-scan-" .. npc:EntIndex())

					npc:Remove()

					-- === СОЗДАЁМ НОВОГО БОТА ===
					timer.Simple(0.1, function()
						local newNpc = ents.Create("solo_companion_npc")
						if not IsValid(newNpc) then
							return
						end

						newNpc:SetPos(saveData.pos)
						newNpc:Spawn()
						newNpc:Activate()

						-- Восстанавливаем настройки
						timer.Simple(0.2, function()
							if not IsValid(newNpc) then
								return
							end

							-- Модель
							if saveData.model and saveData.model ~= "" then
								newNpc:SetBotModel(saveData.model)
							end

							-- Ник
							if saveData.nick and saveData.nick ~= "" then
								newNpc:SetCustomNick(saveData.nick)
							end

							-- Оружие
							if saveData.combatWeapon then
								newNpc._combatWeaponClass = saveData.combatWeapon
							end
							if saveData.idleWeapon then
								newNpc._idleWeaponClass = saveData.idleWeapon
							end

							-- Режимы
							newNpc._healEnabled = saveData.healEnabled
							newNpc._healThreshold = saveData.healThreshold
							newNpc._defenderMode = saveData.defenderMode
							newNpc._stealthMode = saveData.stealthMode
							newNpc._pacifistMode = saveData.pacifistMode
							newNpc._aggressiveMode = saveData.aggressiveMode

							-- Форсируем Idle
							newNpc._forceIdleNextTick = true

						end)
					end)
				end
			end
		end
	end)
end
