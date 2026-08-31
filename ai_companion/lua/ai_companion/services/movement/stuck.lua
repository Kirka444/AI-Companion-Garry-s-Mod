
local Stuck = {}

function Stuck:new(utils_movement, constants, navmesh)
    local obj = {
        utils = utils_movement,
        constants = constants,
        _const = constants and constants:get() or {},
        navmesh = navmesh,
    }
    obj.utils_movement = utils_movement
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function Stuck:IsValid(ent)
    return self.utils and self.utils:IsValid(ent)
end

function Stuck:GetNavMesh()
    return self.navmesh
end

function Stuck:GetConst()
    if self._const then return self._const end
    if self.constants and self.constants.get then
        self._const = self.constants:get()
        return self._const
    end

    return {}
end

function Stuck:RegisterPathFailure(bot, st, botPos, wpPos)
    local const = self:GetConst()
    local nav = self:GetNavMesh()

    local bArea = nav:GetNearestAreaSmart(botPos, const.navAreaSearchRadius or 600)
    local wArea = nav:GetNearestAreaSmart(wpPos or st.goal_pos, const.navAreaSearchRadius or 600)
    local gArea = nav:GetNearestAreaSmart(st.goal_pos, const.navAreaSearchRadius or 600)
    local gid = gArea and nav:GetAreaID(gArea) or 0

    local key = ((bArea and nav:GetAreaID(bArea)) or 0) .. ">" .. gid
    local now = CurTime()

    st.stuck = st.stuck or {}
    local stuck = st.stuck

    if stuck.loop_key == key and now - (stuck.loop_reset or 0) < 25 then
        stuck.loop_count = (stuck.loop_count or 0) + 1
    else
        stuck.loop_key = key
        stuck.loop_count = 1
        stuck.loop_reset = now
    end

    if stuck.loop_count >= 4 then
        stuck.loop_count = 0
        local gc = gArea and nav:GetAreaCenter(gArea)
        if gc then
            local safePos = gc + Vector(0, 0, 5)
            local hullTr = util.TraceHull({
                start = safePos + Vector(0, 0, 36), endpos = safePos + Vector(0, 0, 36),
                mins = Vector(-16, -16, 0), maxs = Vector(16, 16, 72), filter = bot
            })
            if not hullTr.Hit then
                bot:SetPos(safePos)
                bot:SetLocalVelocity(Vector(0, 0, 0))
            end
        end
    end
end

function Stuck:Update(bot, cmd, moveDir, st)
    local const = self:GetConst()
    local nav = self:GetNavMesh()

    if not st.stuck then
        st.stuck = {
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
        }
    end
    local stuck = st.stuck

    if not st.repath then
        st.repath = {
            force = false,
            next_force = 0,
            last_wall = 0,
            cooldown = 0,
            last_time = 0,
        }
    end

    if CurTime() < (stuck.unstuck_until or 0) and stuck.unstuck_dir then
        self.utils:ApplyWorldMovement(cmd, stuck.unstuck_dir, 220)
        return true
    end

    local botPos = bot:GetPos()
    local now = CurTime()

    if not bot:IsOnGround() and st.path and #st.path > 0 then
        local vel = bot:GetVelocity()
        if vel and vel.z < -100 then
            local downTr = util.TraceLine({
                start = botPos,
                endpos = botPos - Vector(0, 0, 500),
                filter = bot,
                mask = MASK_PLAYERSOLID
            })
            if downTr.Hit then
                local fallDist = botPos.z - downTr.HitPos.z
                if fallDist > 100 then
                    st.path = nil
                    st.path_index = 1
                    stuck.time = 0
                    stuck.last_dist_to_wp = nil
                    stuck.last_dist_to_goal = nil
                    return false
                end
            end
        end
    end

    stuck.pos_history = stuck.pos_history or {}
    stuck.last_dist_to_goal = stuck.last_dist_to_goal or nil
    stuck.last_dist_to_wp = stuck.last_dist_to_wp or nil

    local wantsMove = moveDir:LengthSqr() > 0.001
        or cmd:GetForwardMove() ~= 0
        or cmd:GetSideMove() ~= 0

    if not wantsMove then
        stuck.time = 0
        stuck.pos = botPos
        stuck.pos_history = {}
        stuck.last_dist_to_wp = nil
        stuck.last_dist_to_goal = nil
        return false
    end

    table.insert(stuck.pos_history, { pos = Vector(botPos), time = now })
    while #stuck.pos_history > 0 and (now - stuck.pos_history[1].time) > (const.stuckHistoryTime or 2.5) do
        table.remove(stuck.pos_history, 1)
    end

    local wp = st.path and st.path[st.path_index]
    local distToWP = math.huge

    if wp then
        local toWP = wp.pos - botPos
        toWP.z = 0
        distToWP = toWP:Length()
        if stuck.last_dist_to_wp and distToWP < stuck.last_dist_to_wp - 2 then
            stuck.time = 0
            stuck.pos = botPos
            stuck.last_dist_to_wp = distToWP
            return false
        end

        local wpRadius = (wp and wp.radius) or (const.waypointRadius or 48)
        if stuck.last_dist_to_wp and math.abs(distToWP - stuck.last_dist_to_wp) < 2
            and distToWP > wpRadius + 10 then
            stuck.no_progress_time = (stuck.no_progress_time or 0) + FrameTime()
            if stuck.no_progress_time > (const.stuckHistoryTime or 2.5) then
                stuck.no_progress_time = 0
                if st.path_index < #st.path then
                    local nextWP = st.path[st.path_index + 1]
                    if nextWP then
                        local toNext = nextWP.pos - botPos
                        toNext.z = 0
                        local nextDist = toNext:Length()
                        if nextDist > 200 then
                            local canReach = nav:CanWalkDirect(botPos + Vector(0,0,36), nextWP.pos + Vector(0,0,36), bot)
                            if not canReach then
                                self:RegisterPathFailure(bot, st, botPos, nextWP.pos)
                                st.path = nil
                                st.path_index = 1
                                st.repath.force = true
                                st.repath.next_force = CurTime() + (const.repathCooldown or 0.3)
                                return false
                            end
                        end
                    end
                    st.path_index = st.path_index + 1
                    stuck.time = 0
                    stuck.pos_history = {}
                    stuck.last_dist_to_wp = nil
                    return false
                else
                    self:RegisterPathFailure(bot, st, botPos, wp and wp.pos or st.goal_pos)
                    st.path = nil
                    st.path_index = 1
                    st.repath.force = true
                    st.repath.next_force = CurTime() + (const.repathCooldown or 0.3)
                    return false
                end
            end
        else
            stuck.no_progress_time = 0
        end
        stuck.last_dist_to_wp = distToWP
    end

    local goalPos = st.goal_pos
    local distToGoal = goalPos and botPos:DistToSqr(goalPos) or math.huge
    if stuck.last_dist_to_goal and distToGoal < stuck.last_dist_to_goal - 100 then
        stuck.time = 0
        stuck.pos = botPos
        stuck.last_dist_to_goal = distToGoal
        return false
    end
    stuck.last_dist_to_goal = distToGoal

    local vel = bot:GetVelocity()
    local speed2D = vel and Vector(vel.x, vel.y, 0):Length() or 0
    local isStuck = false

    if #stuck.pos_history >= (const.stuckMaxHistory or 3) then
        local firstPos = stuck.pos_history[1].pos
        local timeSpan = now - stuck.pos_history[1].time
        if timeSpan >= (const.standStillTimeThreshold or 1.5) then
            local netDisplacement = botPos:Distance(firstPos)
            if netDisplacement < (const.standStillThreshold or 8) and speed2D < (const.standStillSpeedThreshold or 20) then
                isStuck = true
            end
        end
    end

    if not isStuck then
        stuck.time = 0
        stuck.pos = botPos
        return false
    end

    stuck.time = stuck.time + math.max(FrameTime(), 0.001)
    if stuck.time > (const.unstuckTime or 0.7) then
        if st.path and st.path_index < #st.path then
            local nextWP = st.path[st.path_index + 1]
            st.path_index = st.path_index + 1
            stuck.time = 0
            stuck.pos = botPos
            stuck.pos_history = {}
            stuck.last_dist_to_wp = nil
            stuck.no_progress_time = 0
            if nextWP then
                local pushDir = nextWP.pos - botPos
                pushDir.z = 0
                if pushDir:LengthSqr() > 0.001 then
                    pushDir:Normalize()
                    stuck.unstuck_dir = pushDir
                    stuck.unstuck_until = CurTime() + (const.unstuckDuration or 0.45)
                    self.utils_movement:ApplyWorldMovement(cmd, pushDir, 300)
                    cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_JUMP))
                    return true
                end
            end
            return false
        end

        stuck.time = 0
        stuck.pos = botPos
        stuck.pos_history = {}
        stuck.no_progress_time = 0
        st.repath.force = true
        st.repath.next_force = CurTime() + (const.repathCooldown or 0.3)

        local right = moveDir:Angle():Right()
        local options = { right, -right, -moveDir, moveDir }
        local chosen = -moveDir
        for _, opt in ipairs(options) do
            opt.z = 0
            if opt:LengthSqr() > 0.001 then
                opt:Normalize()
                local tr = util.TraceHull({
                    start = botPos + Vector(0, 0, 15),
                    endpos = botPos + Vector(0, 0, 15) + opt * 40,
                    mins = Vector(-12, -12, 0), maxs = Vector(12, 12, 20),
                    filter = bot, mask = MASK_PLAYERSOLID
                })
                if not tr.Hit then
                    chosen = opt
                    break
                end
            end
        end

        stuck.unstuck_dir = chosen
        stuck.unstuck_until = CurTime() + (const.unstuckDuration or 0.45)
        cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_JUMP))
        self.utils:ApplyWorldMovement(cmd, chosen, 220)
        return true
    end

    return false
end

return Stuck
