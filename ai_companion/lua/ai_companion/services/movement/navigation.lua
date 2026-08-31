
local Navigation = {}
function Navigation:new(utils, constants, navmesh, path, doors, stuck, stealth)
    local obj = {
        utils = utils,
        constants = constants,
        navmesh = navmesh,
        path = path,
        doors = doors,
        stuck = stuck,
        stealth = stealth,
        _navMeshAvailable = nil,
        _lastNavCheck = 0,
        _navCheckInterval = 5.0,
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function Navigation:IsValid(ent)
    return self.utils and self.utils:IsValid(ent)
end

function Navigation:GetConst()
    return self.constants and self.constants:get() or {}
end

function Navigation:GetNavMesh()
    return self.navmesh
end

function Navigation:IsNavMeshAvailable()
    local now = CurTime()
    if now - self._lastNavCheck < self._navCheckInterval then
        return self._navMeshAvailable
    end

    self._lastNavCheck = now

    if not navmesh then
        self._navMeshAvailable = false
        return false
    end

    local ok, loaded = pcall(function() return navmesh.IsLoaded() end)
    self._navMeshAvailable = ok and loaded

    if not self._navMeshAvailable and self.utils then
        MsgC(Color(255, 200, 100), "[AI Companion] WARN: NavMesh не доступен на этой карте! Используется режим прямой навигации.\n")
    end

    return self._navMeshAvailable
end

function Navigation:GetNavState(bot, data)
    if not self:IsValid(bot) then return nil end
    if not data then return nil end

    local nav = data.navigation
    if not nav then
        nav = {
            path = nil,
            path_index = 1,
            goal_pos = Vector(0, 0, 0),
            target_key = -1,
            fail_count = 0,
            disabled_until = 0,
            stuck = {
                pos = Vector(0, 0, 0),
                time = 0,
                unstuck_dir = nil,
                unstuck_until = 0,
                pos_history = {},
                no_progress_time = 0,
                wp_stuck_time = 0,
                wp_stuck_pos = Vector(0, 0, 0),
                last_dist_to_goal = nil,
                last_dist_to_wp = nil,
                loop_key = nil,
                loop_count = 0,
                loop_reset = 0,
                teleport_fails = 0,
                in_narrow_passage = false,
            },
            repath = {
                force = false,
                next_force = 0,
                last_wall = 0,
                cooldown = 0,
                last_time = 0,
            },
            door_wait = 0,
            slide_time = 0,
            area_cache = {
                pos = Vector(0, 0, 0),
                area = nil,
                time = 0,
            },
        }
        data.navigation = nav
    end

    return nav
end

function Navigation:ShouldStop(bot, st, targetPos)
    local const = self:GetConst()
    local botPos = bot:GetPos()
    local distToTarget = botPos:DistToSqr(targetPos)
    return distToTarget < const.closeFollowDistSq
end

function Navigation:TeleportToTarget(bot, targetPos, moveTarget, st)
    if not st then return false end
    local const = self:GetConst()

    st._teleportFails = st._teleportFails or 0
    if st._teleportFails > const.teleportFailLimit then
        st._teleportFails = 0
        st.disabledUntil = CurTime() + const.teleportFallbackTimeout
        return false
    end

    local back = Vector(0, 0, 0)
    if self:IsValid(moveTarget) then
        local ok, fwd = pcall(function() return moveTarget:GetForward() end)
        if ok and fwd then back = fwd * -80 end
    end

    local safePos = targetPos + back
    local tr = util.TraceLine({
        start = safePos + Vector(0, 0, 50),
        endpos = safePos - Vector(0, 0, 200),
        filter = self:IsValid(moveTarget) and moveTarget or bot,
        mask = MASK_PLAYERSOLID
    })
    if tr.Hit then safePos = tr.HitPos + Vector(0, 0, 5) end

    local hullTr = util.TraceHull({
        start = safePos + Vector(0, 0, 36),
        endpos = safePos + Vector(0, 0, 36),
        mins = Vector(-16, -16, 0),
        maxs = Vector(16, 16, 72),
        filter = bot
    })

    if not hullTr.Hit then
        bot:SetPos(safePos)
        bot:SetLocalVelocity(Vector(0, 0, 0))
        st.path = nil
        st.path_index = 1
        st.repath.last_time = 0
        st.repath.force = true
        st.repath.next_force = CurTime() + const.repathCooldown
        st._teleportFails = 0
        return true
    else
        st._teleportFails = st._teleportFails + 1
    end

    return false
end

function Navigation:NavigateDirect(bot, cmd, targetPos, moveTarget, st)
    if not self:IsValid(bot) or not cmd then return end

    local const = self:GetConst()
    local botPos = bot:GetPos()
    local distToTarget = botPos:DistToSqr(targetPos)

    if distToTarget < const.closeFollowDistSq then
        cmd:ClearMovement()
        cmd:ClearButtons()
        local lookAng = self.utils:GetLookAngle(bot, moveTarget or targetPos)
        cmd:SetViewAngles(lookAng)
        bot:SetEyeAngles(lookAng)
        return
    end

    if distToTarget > const.teleportDist * const.teleportDist then
        if self:TeleportToTarget(bot, targetPos, moveTarget, st) then
            return
        end
    end

    self:MoveDirect(bot, cmd, targetPos, moveTarget, st)
end

function Navigation:TryDirectMovement(bot, cmd, targetPos, moveTarget, st)
    if not self:IsValid(bot) or not cmd then return false end
    local const = self:GetConst()
    local botPos = bot:GetPos()
    local distToTarget = botPos:DistToSqr(targetPos)

    if distToTarget < const.directPathMinDist * const.directPathMinDist then
        self:MoveDirect(bot, cmd, targetPos, moveTarget, st)
        return true
    end

    if distToTarget < const.directPathMaxDistSq then
        local trace = util.TraceHull({
            start = botPos + Vector(0, 0, 36),
            endpos = targetPos + Vector(0, 0, 36),
            mins = Vector(-14, -14, 0),
            maxs = Vector(14, 14, 48),
            filter = bot,
            mask = MASK_PLAYERSOLID
        })

        if not trace.Hit and not trace.StartSolid then
            self:MoveDirect(bot, cmd, targetPos, moveTarget, st)
            return true
        end
    end

    return false
end

function Navigation:MoveDirect(bot, cmd, targetPos, moveTarget, st)
    if not self:IsValid(bot) or not cmd then return end

    local const = self:GetConst()
    local targetIsNoclip = self.utils:IsTargetNoclip(moveTarget)

    if targetIsNoclip then
        self.utils:ClearDuckFlags(bot)
        cmd:SetButtons(bit.band(cmd:GetButtons(), bit.bnot(IN_DUCK)))
    end

    local botPos = bot:GetPos()
    local dir = targetPos - botPos
    dir.z = 0
    if dir:LengthSqr() <= 1 then return end
    dir:Normalize()

    local blocked, wallTr = self:ResolveWall(bot, dir, st, moveTarget)

    if bot:IsOnGround() then
        local ground = util.TraceLine({
            start = botPos + Vector(0, 0, 10),
            endpos = botPos - Vector(0, 0, 20),
            filter = bot,
            mask = MASK_PLAYERSOLID
        })
        if ground.Hit and ground.HitNormal.z > 0.3 and ground.HitNormal.z < 0.99 then
            local n = ground.HitNormal
            dir = dir - n * dir:Dot(n)
            if dir:LengthSqr() > 0.001 then dir:Normalize() end
        end
    end

    if self.doors:HandleDoor(bot, cmd, dir, st) then return end

    local jump = self:ShouldJump(bot, dir, blocked, wallTr, nil)
    local crouch = (not targetIsNoclip) and (self:ShouldCrouch(bot, dir, moveTarget) or (bot._aiStealthCrouch == true))
    local speed, wantSprint = self:GetBotMoveSpeed(bot, botPos:DistToSqr(targetPos), crouch)
    local lookAng = self.utils:GetLookAngle(bot, moveTarget or targetPos)

    cmd:SetViewAngles(lookAng)
    bot:SetEyeAngles(lookAng)

    local btns = cmd:GetButtons()
    if wantSprint then
        btns = bit.bor(btns, IN_SPEED)
    else
        btns = bit.band(btns, bit.bnot(IN_SPEED))
    end

    if crouch then
        btns = bit.bor(btns, IN_DUCK)
        bot:AddFlags(FL_DUCKING)
        bot:AddFlags(FL_ANIMDUCKING)
    else
        btns = bit.band(btns, bit.bnot(IN_DUCK))
        bot:RemoveFlags(FL_DUCKING)
        bot:RemoveFlags(FL_ANIMDUCKING)
    end

    if jump then btns = bit.bor(btns, IN_JUMP) end

    cmd:SetButtons(btns)
    self.utils:ApplyWorldMovement(cmd, dir, speed)
end

function Navigation:AdvanceWaypoints(bot, st)
    local const = self:GetConst()
    local botPos = bot:GetPos()

    if st.path and st.path_index == 1 and #st.path > 1 then
        local wp1 = st.path[1]
        if wp1 and wp1.type == "walk" then
            local d = wp1.pos:DistToSqr(botPos)
            if d < (wp1.radius or const.waypointRadius) * (wp1.radius or const.waypointRadius) then
                st.path_index = 2
                if st.path[2] then
                    st.path[2]._enterTime = nil
                    st.path[2]._enterPos = nil
                    st.path[2]._bestDist = nil
                end
            end
        end
    end

    local guard = 0
    while st.path and st.path_index <= #st.path and guard < const.maxWaypointAdvance do
        guard = guard + 1
        local wp = st.path[st.path_index]
        if not wp then break end

        local to = wp.pos - botPos
        local dist = to:Length()
        local radius = wp.radius or const.waypointRadius
        local flatDist = Vector(to.x, to.y, 0):Length()
        local heightDiff = math.abs(wp.pos.z - botPos.z)

        if not wp._enterTime then
            wp._enterTime = CurTime()
            wp._enterPos = Vector(botPos)
            wp._bestDist = dist
        end
        if wp._bestDist == nil then wp._bestDist = dist end

        local timeOnWP = CurTime() - (wp._enterTime or 0)
        local movedOnWP = wp._enterPos and wp._enterPos:DistToSqr(botPos) or 999999

        if dist < wp._bestDist then
            wp._bestDist = dist
            wp._enterTime = CurTime()
            wp._enterPos = Vector(botPos)
        end

        local shouldSkip = false

        if wp.type:find("stairs") then
            radius = 120
            local vel = bot:GetVelocity()
            local vel2D = vel and Vector(vel.x, vel.y, 0):Length() or 0
            if vel and math.abs(vel.z) > 15 then
                shouldSkip = true
            elseif vel2D > 40 and flatDist < radius then
                shouldSkip = true
            elseif timeOnWP > const.stairsSkipTime and movedOnWP < const.stairsMinMoveSq then
                shouldSkip = true
            end
        elseif wp.type == "drop" then
            if botPos.z < wp.pos.z - 15 then
                shouldSkip = true
            elseif flatDist < radius then
                shouldSkip = true
            elseif timeOnWP > const.forceWPSkipTime and movedOnWP < const.forceWPSkipMinMove then
                shouldSkip = true
            end
        else
            if dist < radius then
                shouldSkip = true
            elseif flatDist < radius * 0.7 and heightDiff < 50 then
                shouldSkip = true
            elseif timeOnWP > const.forceWPSkipTime and movedOnWP < const.forceWPSkipMinMove then
                shouldSkip = true
            elseif heightDiff > 80 and flatDist < radius * 0.5 and timeOnWP > const.heightSkipTime then
                shouldSkip = true
            end
        end

        if shouldSkip then
            st.path_index = st.path_index + 1
            if st.path[st.path_index] then
                st.path[st.path_index]._enterTime = nil
                st.path[st.path_index]._enterPos = nil
                st.path[st.path_index]._bestDist = nil
            end
        else
            break
        end
    end

    if st.path and st.path_index > #st.path then st.path = nil end
end

function Navigation:NavigatePath(bot, cmd, st, moveTarget)
    if not st.path or #st.path == 0 then return end

    self:AdvanceWaypoints(bot, st)
    local wp = st.path and st.path[st.path_index]
    if not wp then return end

    local botPos = bot:GetPos()
    local steerPos = self:GetSteerPosition(botPos, st.path, st.path_index)
    local moveDir = steerPos - botPos

    local heightDiff2 = math.abs(moveDir.z)
    if heightDiff2 > 20 then
        moveDir.z = math.Clamp(moveDir.z, -100, 100)
    else
        moveDir.z = 0
    end

    if moveDir:LengthSqr() < 0.001 then
        moveDir = st.goal_pos - botPos
        moveDir.z = 0
    end
    moveDir:Normalize()
    moveDir = self:GetAvoidanceDir(bot, moveDir, moveTarget)

    local moveDir, blocked, wallTr = self:ResolveWall(bot, moveDir, st, moveTarget)

    if blocked and bot:IsOnGround() then
        local ent = wallTr and wallTr.Entity
        local isDoor = self:IsValid(ent) and ((ent:GetClass() or ""):find("door") or (ent:GetName() or ""):find("door"))
        if not isDoor then
            st.slide_time = (st.slide_time or 0) + FrameTime()
            if st.slide_time > 1.5 then
                st.slide_time = 0
                local wpNow = st.path and st.path[st.path_index]
                if wpNow then
                    local bA = self.navmesh:GetNearestAreaCached(botPos, 300, st)
                    local wA = wpNow.area or self.navmesh:GetNearestAreaSmart(wpNow.pos, 300)
                    local bId = bA and self.navmesh:GetAreaID(bA)
                    local wId = wA and self.navmesh:GetAreaID(wA)
                    if bId and wId and bId ~= wId then
                        st.repath.force = true
                        st.repath.next_force = CurTime() + 0.3
                    end
                end
            end
        end
    else
        st.slide_time = 0
    end

    if self.doors:HandleDoor(bot, cmd, moveDir, st) then return end

    local nextWP = st.path and st.path[st.path_index + 1]

    local jump = self:ShouldJump(bot, moveDir, blocked, wallTr, nextWP)
    local data = self.data and self.data:GetBotData(bot)
    local isCombat = data and data.combat and self:IsValid(data.combat.target)
    local crouch = (not isCombat) and self:ShouldCrouch(bot, moveDir, moveTarget) or (bot._aiStealthCrouch == true)
    local isOnStairs = wp and wp.type:find("stairs")
    local speed, wantSprint = self:GetBotMoveSpeed(bot, botPos:DistToSqr(st.goal_pos), crouch, isOnStairs)
    local lookAng = self.utils:GetLookAngle(bot, moveTarget or st.goal_pos)

    cmd:SetViewAngles(lookAng)
    bot:SetEyeAngles(lookAng)

    local btns = cmd:GetButtons()
    if wantSprint then
        btns = bit.bor(btns, IN_SPEED)
    else
        btns = bit.band(btns, bit.bnot(IN_SPEED))
    end

    if crouch then
        btns = bit.bor(btns, IN_DUCK)
        bot:AddFlags(FL_DUCKING)
        bot:AddFlags(FL_ANIMDUCKING)
    else
        btns = bit.band(btns, bit.bnot(IN_DUCK))
        bot:RemoveFlags(FL_DUCKING)
        bot:RemoveFlags(FL_ANIMDUCKING)
    end

    if jump then btns = bit.bor(btns, IN_JUMP) end

    cmd:SetButtons(btns)
    self.utils:ApplyWorldMovement(cmd, moveDir, speed)

    local stuckOverride = self.stuck:Update(bot, cmd, moveDir, st)
    if stuckOverride then return end
end

function Navigation:GetSteerPosition(botPos, wps, index)
    if not wps or #wps == 0 then return botPos end
    if index > #wps then return wps[#wps].pos end
    return wps[index].pos
end

function Navigation:UpdateNavigation(bot, cmd, targetPos, moveTarget)
    local data = self.data and self.data:GetBotData(bot)
    local st = self:GetNavState(bot, data)
    if not st then return end

    if self:ShouldStop(bot, st, targetPos) then
        cmd:ClearMovement()
        cmd:ClearButtons()
        st.path = nil
        st.path_index = 1
        st.stuck.time = 0
        local lookAng = self.utils:GetLookAngle(bot, moveTarget or targetPos)
        cmd:SetViewAngles(lookAng)
        bot:SetEyeAngles(lookAng)
        return
    end

    if self:TryDirectMovement(bot, cmd, targetPos, moveTarget, st) then
        return
    end

    local navAvailable = self:IsNavMeshAvailable()
    if not navAvailable then
        self:NavigateDirect(bot, cmd, targetPos, moveTarget, st)
        return
    end

    if self.path:ShouldRepath(bot, st, targetPos, moveTarget) then
        self.path:BuildPath(bot, st, targetPos, moveTarget)
    end

    if not st.path or #st.path == 0 then
        self:MoveDirect(bot, cmd, targetPos, moveTarget, st)
        return
    end

    self:NavigatePath(bot, cmd, st, moveTarget)
end

function Navigation:ResolveWall(bot, moveDir, st, moveTarget)
    local const = self:GetConst()
    local botPos = bot:GetPos()
    local tr = util.TraceHull({
        start = botPos + Vector(0, 0, 15),
        endpos = botPos + Vector(0, 0, 15) + moveDir * const.wallSlideDistance,
        mins = Vector(-12, -12, 0),
        maxs = Vector(12, 12, const.wallSlideHeight),
        filter = bot,
        mask = MASK_PLAYERSOLID
    })

    if not tr.Hit or tr.StartSolid then return moveDir, false, false end
    if self:IsValid(tr.Entity) and self:IsValid(moveTarget) and tr.Entity == moveTarget then
        return moveDir, false, false
    end

    local class = ""
    if self:IsValid(tr.Entity) then
        local ok, c = pcall(function() return tr.Entity:GetClass() end)
        if ok and c then class = c end
    end
    if class:find("door") then return moveDir, false, false end

    local n = tr.HitNormal
    if n.z > 0.7 then return moveDir, false, false end
    n.z = 0
    if n:LengthSqr() < 0.001 then return moveDir, false, false end
    n:Normalize()

    local slide = moveDir - (moveDir:Dot(n) * n)
    slide.z = 0
    if slide:LengthSqr() > 0.001 then
        slide:Normalize()
        local slideTr = util.TraceHull({
            start = botPos + Vector(0, 0, 15),
            endpos = botPos + Vector(0, 0, 15) + slide * const.wallSlideCheckDistance,
            mins = Vector(-12, -12, 0),
            maxs = Vector(12, 12, const.wallSlideHeight),
            filter = bot,
            mask = MASK_PLAYERSOLID
        })
        if not slideTr.Hit then return slide, true, tr end
    end

    local right = moveDir:Angle():Right()
    local candidates = { right, -right, -moveDir }
    for _, cand in ipairs(candidates) do
        cand.z = 0
        if cand:LengthSqr() > 0.001 then
            cand:Normalize()
            local cTr = util.TraceHull({
                start = botPos + Vector(0, 0, 15),
                endpos = botPos + Vector(0, 0, 15) + cand * const.wallSlideCheckDistance,
                mins = Vector(-12, -12, 0),
                maxs = Vector(12, 12, const.wallSlideHeight),
                filter = bot,
                mask = MASK_PLAYERSOLID
            })
            if not cTr.Hit then return cand, true, tr end
        end
    end
    return -moveDir, true, tr
end

function Navigation:GetAvoidanceDir(bot, moveDir, moveTarget)
    local const = self:GetConst()
    local botPos = bot:GetPos()
    local avoid = Vector(0, 0, 0)
    local nearby = ents.FindInSphere(botPos, const.avoidanceRadius) or {}

    for _, ent in ipairs(nearby) do
        if ent == bot then continue end
        if self:IsValid(moveTarget) and ent == moveTarget then continue end
        if not self:IsValid(ent) then continue end
        if not (ent:IsPlayer() or ent:IsNPC()) then continue end
        if ent:IsPlayer() and not ent:Alive() then continue end
        if ent:IsNPC() then
            local ok, alive = pcall(function() return ent:Alive() end)
            if ok and not alive then continue end
        end

        local diff = botPos - ent:GetPos()
        diff.z = 0
        local d = diff:Length()
        if d > 1 and d < const.obstacleMinDistance then
            diff:Normalize()
            avoid = avoid + diff * ((const.obstacleMinDistance - d) / const.obstacleMinDistance)
        end
    end

    if avoid:LengthSqr() < 0.01 then return moveDir end

    local candidate = (moveDir * const.obstacleMoveFactor + avoid * const.obstacleAvoidFactor)
    if candidate:LengthSqr() < 0.001 then return moveDir end
    candidate:Normalize()

    local tr = util.TraceHull({
        start = botPos + Vector(0, 0, 15),
        endpos = botPos + Vector(0, 0, 15) + candidate * const.obstacleCheckDistance,
        mins = Vector(-12, -12, 0),
        maxs = Vector(12, 12, const.wallSlideHeight),
        filter = bot,
        mask = MASK_PLAYERSOLID
    })
    if not tr.Hit then return candidate end
    return moveDir
end

function Navigation:ShouldJump(bot, moveDir, blocked, wallTr, nextWP)
    if not bot:IsOnGround() then return false end
    local const = self:GetConst()
    local botPos = bot:GetPos()

    if nextWP and nextWP.type:find("stairs") then return false end
    if nextWP and nextWP.type == "drop" then
        local toWP = nextWP.pos - botPos
        if toWP:LengthSqr() > 0.001 then
            toWP:Normalize()
            local dot = moveDir:Dot(toWP)
            if dot > 0.7 then return true end
        end
    end

    if nextWP and nextWP.pos.z - botPos.z > const.jumpZThreshold then
        local flatDist = Vector(nextWP.pos.x - botPos.x, nextWP.pos.y - botPos.y, 0):Length()
        if flatDist < const.jumpFlatDist then return true end
    end

    local forward = Vector(moveDir.x, moveDir.y, 0)
    if forward:LengthSqr() > 0.001 then
        forward:Normalize()
        local stepCheck = util.TraceLine({
            start = botPos + Vector(0, 0, 18),
            endpos = botPos + Vector(0, 0, 18) + forward * 30,
            filter = bot,
            mask = MASK_PLAYERSOLID
        })
        if stepCheck.Hit and not stepCheck.StartSolid then
            local height = stepCheck.HitPos.z - botPos.z
            if height > const.jumpHeightMin and height < const.jumpHeightMax then
                local topCheck = util.TraceHull({
                    start = stepCheck.HitPos + Vector(0, 0, 2) + forward * 10,
                    endpos = stepCheck.HitPos + Vector(0, 0, 2) + forward * 10 + Vector(0, 0, const.jumpCheckHeight),
                    mins = Vector(-16, -16, 0),
                    maxs = Vector(16, 16, 0),
                    filter = bot,
                    mask = MASK_PLAYERSOLID
                })
                if not topCheck.Hit then return true end
            end
        end
    end

    local checkPos = botPos + moveDir * const.jumpCheckDist
    local gap = util.TraceHull({
        start = checkPos + Vector(0, 0, 10),
        endpos = checkPos - Vector(0, 0, 200),
        mins = Vector(-16, -16, 0),
        maxs = Vector(16, 16, 0),
        filter = bot,
        mask = MASK_PLAYERSOLID
    })
    if not gap.Hit then return true end

    if blocked and wallTr and type(wallTr) == "table" and wallTr.Hit then
        local wallHeight = wallTr.HitPos.z - botPos.z
        if wallHeight > 0 and wallHeight < const.maxClimbHeight then
            local topPos = wallTr.HitPos + Vector(0, 0, 2) + moveDir * 20
            local top = util.TraceHull({
                start = topPos,
                endpos = topPos + Vector(0, 0, 60),
                mins = Vector(-16, -16, 0),
                maxs = Vector(16, 16, const.jumpCheckHeight),
                filter = bot,
                mask = MASK_PLAYERSOLID
            })
            if not top.Hit then return true end
        end
    end
    return false
end

function Navigation:ShouldCrouch(bot, moveDir, moveTarget)
    local stealthMode = bot:GetNWBool("AI_StealthMode", false)

    if stealthMode and bot._aiStealthCrouch then
        return true
    end

    return false
end

function Navigation:GetBotMoveSpeed(bot, distSqr, crouching, forceRun)
    if not self:IsValid(bot) then return 200, false end
    local const = self:GetConst()

    if forceRun then
        local runSpeed = const.runSpeed
        local ok, w = pcall(function() return bot:GetRunSpeed() end)
        if ok and tonumber(w) and w > 0 then runSpeed = tonumber(w) end
        return math.Clamp(runSpeed, const.speedMin, const.speedMax), true
    end

    if crouching then
        return const.crouchSpeed, false
    end

    local walkSpeed = const.walkSpeed
    local runSpeed = const.runSpeed
    local ok, w = pcall(function() return bot:GetWalkSpeed() end)
    if ok and tonumber(w) and w > 0 then walkSpeed = tonumber(w) end
    ok, w = pcall(function() return bot:GetRunSpeed() end)
    if ok and tonumber(w) and w > 0 then runSpeed = tonumber(w) end

    walkSpeed = math.Clamp(walkSpeed, const.speedMin, const.speedMax)
    runSpeed = math.Clamp(runSpeed, walkSpeed, const.speedMax)

    local dist = math.sqrt(math.max(distSqr or 0, 0))
    if dist > const.fastDist then
        return runSpeed, true
    else
        return walkSpeed, false
    end
end

return Navigation
