
local Path = {}

function Path:new(utils, constants, navmesh)
    local obj = {
        utils = utils,
        constants = constants,
        navmesh = navmesh,
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function Path:IsValid(ent)
    return self.utils and self.utils:IsValid(ent)
end

function Path:GetConst()
    return self.constants and self.constants:get() or {}
end

function Path:GetNavMesh()
    return self.navmesh
end

function Path:BuildWaypoints(steps, startPos, goalPos)
    if not steps or #steps == 0 then return nil end
    if not startPos or not isvector(startPos) then return nil end
    if not goalPos or not isvector(goalPos) then return nil end

    local const = self:GetConst()
    local nav = self:GetNavMesh()
    local wps = {}

    table.insert(wps, { pos = Vector(startPos), type = "walk", radius = const.waypointRadius })

    for i = 2, #steps - 1 do
        local st = steps[i]
        if st.area and nav:IsValid(st.area) then
            local center = nav:GetAreaCenter(st.area)
            if center and isvector(center) then
                local isObstacle = nav:IsAreaObstacle(st.area)
                local isBlocked = nav:IsAreaBlocked(st.area)
                local isStairs = nav:IsAreaStairs(st.area)

                if isBlocked then

                elseif isStairs then
                    local prevArea = steps[i-1] and steps[i-1].area
                    local nextArea = steps[i+1] and steps[i+1].area
                    if prevArea and nextArea then
                        local stairsWPs = nav:GetStairsWaypoints(st.area, prevArea, nextArea)
                        if stairsWPs then
                            for _, swp in ipairs(stairsWPs) do
                                table.insert(wps, swp)
                            end
                        else
                            table.insert(wps, { pos = Vector(center), type = "walk", area = st.area, radius = const.waypointRadius })
                        end
                    else
                        table.insert(wps, { pos = Vector(center), type = "walk", area = st.area, radius = const.waypointRadius })
                    end
                else
                    local wpPos = Vector(center)
                    local radius = const.waypointRadius
                    if isObstacle then
                        local prevArea = steps[i-1] and steps[i-1].area
                        local entryPoint = prevArea and nav:GetAreaEntryPoint(st.area, prevArea)
                        if entryPoint then
                            wpPos = Vector(entryPoint.x, entryPoint.y, center.z)
                            radius = 24
                        end
                    else
                        local prevPos = wps[#wps].pos
                        local zDiff = math.abs(center.z - prevPos.z)
                        if zDiff > 25 then
                            local downTr = util.TraceLine({
                                start = center + Vector(0,0,10),
                                endpos = center - Vector(0,0,100),
                                mask = MASK_PLAYERSOLID
                            })
                            if downTr.Hit then
                                local shelfPos = Vector(center.x, center.y, downTr.HitPos.z)
                                if nav:CanWalkDirect(prevPos, shelfPos, nil) then
                                    table.insert(wps, { pos = shelfPos, type = "walk", radius = const.waypointRadius })
                                end
                            end
                        end
                    end
                    table.insert(wps, { pos = wpPos, type = "walk", area = st.area, radius = radius })
                end
            end
        end
    end

    local goalArea = nav:GetNearestArea(goalPos, 200)
    if goalArea and nav:IsValid(goalArea) then
        local snapped = nav:GetAreaClosest(goalArea, goalPos)
        if snapped and isvector(snapped) and math.abs(snapped.z - goalPos.z) < 40 then
            table.insert(wps, { pos = snapped, type = "walk", radius = const.waypointRadius })
        else
            table.insert(wps, { pos = Vector(goalPos), type = "walk", radius = const.waypointRadius })
        end
    else
        table.insert(wps, { pos = Vector(goalPos), type = "walk", radius = const.waypointRadius })
    end

    return wps
end

function Path:BuildNoclipPath(bot, st, targetPos, moveTarget)
    local const = self:GetConst()
    local nav = self:GetNavMesh()

    if not self:IsValid(moveTarget) or not moveTarget:IsPlayer() or not self.utils:IsTargetNoclip(moveTarget) then
        return false
    end

    local botPos = bot:GetPos()
    local noclipDist = botPos:DistToSqr(targetPos)
    if noclipDist < const.teleportMaxDistSq then
        if nav:CanWalkDirect(botPos, targetPos, bot) then
            st.path = {
                { pos = Vector(botPos), type = "walk", radius = const.waypointRadius },
                { pos = Vector(targetPos), type = "walk", radius = const.waypointRadius }
            }
            st.path_index = 1
            return true
        end
    end
    return false
end

function Path:BuildDirectPath(bot, st, targetPos)
    local const = self:GetConst()
    local nav = self:GetNavMesh()
    local botPos = bot:GetPos()
    if botPos:DistToSqr(targetPos) < const.directPathDistSq then
        st.path = {
            { pos = Vector(botPos), type = "walk", radius = const.waypointRadius },
            { pos = Vector(targetPos), type = "walk", radius = const.waypointRadius }
        }
        st.path_index = 1
        return true
    end
    return false
end

function Path:BuildNavPath(bot, st, targetPos, moveTarget)
    local const = self:GetConst()
    local nav = self:GetNavMesh()
    local botPos = bot:GetPos()

    if not navmesh or not navmesh.IsLoaded() then return false end

    local startArea = nav:GetNearestAreaCached(botPos, const.navAreaSearchRadius, st)
    local goalArea = nav:GetNearestAreaCached(targetPos, const.navAreaSearchRadius, st)

    if not startArea and not goalArea then
        if nav:CanWalkDirect(botPos, targetPos, bot) then
            st.path = {
                { pos = Vector(botPos), type = "walk", radius = const.waypointRadius },
                { pos = Vector(targetPos), type = "walk", radius = const.waypointRadius }
            }
            st.path_index = 1
            return true
        end
        if botPos:DistToSqr(targetPos) > const.teleportDist * const.teleportDist then
            return false
        end
        return false
    end

    if startArea and not goalArea then
        local nearestPoint = nav:GetNearestArea(targetPos, const.teleportSearchRadius)
        if nearestPoint then goalArea = nearestPoint end
    end

    if not startArea and goalArea then
        local nearestNav = nav:GetNearestArea(botPos, const.teleportSearchRadius)
        if nearestNav then
            local navCenter = nav:GetAreaCenter(nearestNav)
            if navCenter and nav:CanWalkDirect(botPos, navCenter, bot) then
                st.path = {
                    { pos = Vector(botPos), type = "walk", radius = const.waypointRadius },
                    { pos = navCenter, type = "walk", radius = const.waypointRadius }
                }
                st.path_index = 1
                return true
            end
        end
    end

    if not startArea or not goalArea then return false end

    local steps = nav:FindPath(startArea, goalArea, false)
    if not steps then
        steps = nav:FindPath(startArea, goalArea, true)
    end

    if not steps then
        local altGoal = nav:GetNearestAreaSmart(targetPos, const.teleportSearchRadius)
        if altGoal and altGoal ~= goalArea then
            local altSteps = nav:FindPath(startArea, altGoal, true)
            if altSteps then
                steps = altSteps
                goalArea = altGoal
            end
        end
    end

    if not steps then
        if nav:CanWalkDirect(botPos, targetPos, bot) then
            st.path = {
                { pos = Vector(botPos), type = "walk", radius = const.waypointRadius },
                { pos = Vector(targetPos), type = "walk", radius = const.waypointRadius }
            }
            st.path_index = 1
            return true
        end
        st.fail_count = (st.fail_count or 0) + 1
        if st.fail_count > const.maxPathRetries then
            st.fail_count = 0
            st.disabled_until = CurTime() + const.navDisabledTime
        end
        st.path = nil
        return false
    end

    local raw = self:BuildWaypoints(steps, botPos, targetPos)
    if raw and #raw > 0 then
        if st.path and st.path_index > 1 and st.target_key == (self:IsValid(moveTarget) and moveTarget:EntIndex() or -1) then
            local oldWP = st.path[st.path_index]
            if oldWP then
                local closestIdx = 1
                local closestDist = math.huge
                for i, wp in ipairs(raw) do
                    local d = wp.pos:DistToSqr(oldWP.pos)
                    if d < closestDist then
                        closestDist = d
                        closestIdx = i
                    end
                end
                st.path_index = math.max(1, closestIdx)
            else
                st.path_index = 1
            end
        else
            st.path_index = 1
        end
        st.path = raw
        st.fail_count = 0
        return true
    end

    return false
end

function Path:BuildPath(bot, st, targetPos, moveTarget)
    if self:BuildNoclipPath(bot, st, targetPos, moveTarget) then return true end
    if self:BuildDirectPath(bot, st, targetPos) then return true end
    return self:BuildNavPath(bot, st, targetPos, moveTarget)
end

function Path:ShouldRepath(bot, st, targetPos, moveTarget)
    local const = self:GetConst()

    st.disabled_until = st.disabled_until or 0
    st.repath = st.repath or {}
    st.repath.cooldown = st.repath.cooldown or 0
    st.repath.force = st.repath.force or false
    st.repath.next_force = st.repath.next_force or 0
    st.path_index = st.path_index or 1
    st.target_key = st.target_key or -1
    st.goal_pos = st.goal_pos or Vector(0, 0, 0)
    st.repath.last_time = st.repath.last_time or 0

    if CurTime() < st.disabled_until then return false end
    if CurTime() < st.repath.cooldown then return false end

    if st.repath.force and CurTime() >= st.repath.next_force then
        st.repath.force = false
        st.repath.cooldown = CurTime() + const.repathCooldown
        return true
    elseif not st.path or #st.path == 0 or st.path_index > #st.path then
        st.repath.cooldown = CurTime() + const.repathCooldown
        return true
    else
        local key = self:IsValid(moveTarget) and moveTarget:EntIndex() or -1
        if st.target_key ~= key then
            st.repath.cooldown = CurTime() + const.repathCooldown
            return true
        else
            local goalMoved = st.goal_pos:DistToSqr(targetPos)
            if goalMoved > const.minGoalMoveForRepath * 8 then
                st.repath.cooldown = CurTime() + const.repathCooldownLarge
                return true
            elseif CurTime() - st.repath.last_time > const.recalcInterval
                   and goalMoved > const.minGoalMoveForRepath * 3 then
                st.repath.cooldown = CurTime() + const.repathCooldownMedium
                return true
            end
        end
    end
    return false
end

return Path
