if AI_COMPANION_MOVEMENT_LOADED then return end
AI_COMPANION_MOVEMENT_LOADED = true
local AC = _G.AI_COMPANION
local NAV_MESH_INVALID      = 0
local NAV_MESH_CROUCH       = 1
local NAV_MESH_JUMP         = 2
local NAV_MESH_PRECISE      = 4
local NAV_MESH_NO_JUMP      = 8
local NAV_MESH_STOP         = 16
local NAV_MESH_RUN          = 32
local NAV_MESH_WALK         = 64
local NAV_MESH_AVOID        = 128
local NAV_MESH_TRANSIENT    = 256
local NAV_MESH_BLOCKED      = 512
local NAV_MESH_HAS_ELEVATOR = 1024
local NAV_MESH_FUNC_COST    = 2048
local NAV_MESH_OBSTACLE_TOP = 16384
local NAV_MESH_CLIFF        = 32768
if not ApplyWorldMovement then
    function ApplyWorldMovement(cmd, moveVec, speed)
        if not cmd then return end
        if not moveVec or moveVec:LengthSqr() <= 1e-4 then return end
        if not speed or speed <= 0 then return end
        local viewAng = cmd:GetViewAngles()
        local fwd = viewAng:Forward()
        fwd.z = 0
        fwd:Normalize()
        local rgt = viewAng:Right()
        rgt.z = 0
        rgt:Normalize()
        cmd:SetForwardMove(moveVec:Dot(fwd) * speed)
        cmd:SetSideMove(moveVec:Dot(rgt) * speed)
        local forwardMove = cmd:GetForwardMove()
        local sideMove = cmd:GetSideMove()
        local btns = cmd:GetButtons()
        if forwardMove > 10 then
            btns = bit.bor(btns, IN_FORWARD)
        elseif forwardMove < -10 then
            btns = bit.bor(btns, IN_BACK)
        end
        if sideMove > 10 then
            btns = bit.bor(btns, IN_MOVERIGHT)
        elseif sideMove < -10 then
            btns = bit.bor(btns, IN_MOVELEFT)
        end
        cmd:SetButtons(btns)
    end
end
local function GetNPCSpinePos(ent)
    if not IsValid(ent) or not ent:IsNPC() then return nil end
    local names = {"ValveBiped.Bip01_Spine4", "ValveBiped.Bip01_Spine2", "ValveBiped.Bip01_Spine1"}
    for _, n in ipairs(names) do
        local ok, bone = pcall(function() return ent:LookupBone(n) end)
        if ok and bone then
            local ok2, pos = pcall(function() return ent:GetBonePosition(bone) end)
            if ok2 and pos and pos:LengthSqr() > 0.01 then
                return pos
            end
        end
    end
    return nil
end
function IsTargetNoclip(target)
    if not IsValid(target) then return false end
    if not target:IsPlayer() then return false end
    local ok, moveType = pcall(function() return target:GetMoveType() end)
    if ok and moveType then
        return moveType == MOVETYPE_NOCLIP
    end
    return false
end
function GetNoclipFollowPos(bot, target)
    if not IsValid(bot) or not IsValid(target) then return nil end
    local botPos = bot:GetPos()
    local targetPos = target:GetPos()
    local zDiff = math.abs(targetPos.z - botPos.z)
    if zDiff < (AI_CONFIG.Magic.Navigation.NoclipHeightThreshold or 50) then
        return targetPos
    end
    return Vector(targetPos.x, targetPos.y, botPos.z)
end
function ClearDuckFlags(bot)
    if not IsValid(bot) then return end
    bot:RemoveFlags(FL_DUCKING)
    bot:RemoveFlags(FL_ANIMDUCKING)
    bot._aiStealthCrouch = false
end
local function IsVectorValue(v)
    if type(v) == "Vector" then return true end
    if type(v) == "table" and v.x and v.y and v.z then return true end
    return false
end
function GetTargetPos(target, bot)
    if not target then return nil end
    if IsVectorValue(target) then
        return Vector(target.x, target.y, target.z)
    end
    if IsValid(target) then
        if bot and target:IsPlayer() and IsTargetNoclip(target) then
            local noclipPos = GetNoclipFollowPos(bot, target)
            if noclipPos then return noclipPos end
        end
        if target:IsPlayer() then
            local ok, pos = pcall(function() return target:EyePos() end)
            if ok and pos then return pos end
        elseif target:IsNPC() then
            local spine = GetNPCSpinePos(target)
            if spine then return spine end
        end
        if target.WorldSpaceCenter then
            local ok, pos = pcall(function() return target:WorldSpaceCenter() end)
            if ok and pos then return pos end
        end
        local ok, pos = pcall(function() return target:GetPos() end)
        if ok and pos then return pos end
    end
    return nil
end
function GetLookAngle(bot, target)
    if not IsValid(bot) then return Angle(0, 0, 0) end
    local lookPos = nil
    if IsVectorValue(target) then
        lookPos = Vector(target.x, target.y, target.z)
    elseif IsValid(target) then
        if target:IsPlayer() then
            local ok, ep = pcall(function() return target:EyePos() end)
            if ok and ep then
                lookPos = ep
            else
                lookPos = target:GetPos() + Vector(0, 0, 64)
            end
        elseif target:IsNPC() then
            local spine = GetNPCSpinePos(target)
            if spine then
                lookPos = spine + Vector(0, 0, 6)
            else
                local ok, pos = pcall(function() return target:WorldSpaceCenter() end)
                lookPos = ok and pos or target:GetPos()
            end
        else
            local ok, pos = pcall(function() return target:WorldSpaceCenter() end)
            if ok and pos then
                lookPos = pos
            else
                ok, pos = pcall(function() return target:GetPos() end)
                lookPos = ok and pos or target:GetPos()
            end
        end
    end
    if not lookPos then
        return bot:GetAngles()
    end
    local lookDir = lookPos - bot:EyePos()
    if lookDir:LengthSqr() < 1 then
        return bot:GetAngles()
    end
    local ang = lookDir:Angle()
    ang.r = 0
    return ang
end
local function GetNearestHuman(bot)
    if not IsValid(bot) then return nil end
    local botPos = bot:GetPos()
    local best = nil
    local bestDist = math.huge
    for _, ply in ipairs(player.GetHumans()) do
        if IsValid(ply) and ply:Alive() and not ply:IsBot() then
            local d = botPos:DistToSqr(ply:GetPos())
            if d < bestDist then
                bestDist = d
                best = ply
            end
        end
    end
    return best
end
local function AddCmdButton(cmd, btn)
    if not cmd or not btn then return end
    cmd:SetButtons(bit.bor(cmd:GetButtons(), btn))
end
local function RemoveCmdButton(cmd, btn)
    if not cmd or not btn then return end
    cmd:SetButtons(bit.band(cmd:GetButtons(), bit.bnot(btn)))
end
local function GetBotMoveSpeed(bot, distSqr, crouching, forceRun)
    if not IsValid(bot) then return 200, false end
    local MAGIC = AI_CONFIG.Magic
    local speeds = MAGIC.Speeds
    local nav = MAGIC.Navigation
    if forceRun then
        local runSpeed = speeds.Run or 320
        local ok, w = pcall(function() return bot:GetRunSpeed() end)
        if ok and tonumber(w) and w > 0 then runSpeed = tonumber(w) end
        return math.Clamp(runSpeed, speeds.Min or 80, speeds.Max or 400), true
    end
    local data = GetBotData(bot)
    local stealthMode = data and data.config and data.config.stealth_mode or false
    if not stealthMode then
        stealthMode = bot:GetNWBool("AI_StealthMode", false)
    end
    if stealthMode and (crouching or bot._aiStealthCrouch) then
        return speeds.Stealth or 80, false
    end
    if crouching then
        return speeds.Crouch or 90, false
    end
    local walkSpeed = speeds.Walk or 200
    local runSpeed = speeds.Run or 320
    local ok, w = pcall(function() return bot:GetWalkSpeed() end)
    if ok and tonumber(w) and w > 0 then walkSpeed = tonumber(w) end
    ok, w = pcall(function() return bot:GetRunSpeed() end)
    if ok and tonumber(w) and w > 0 then runSpeed = tonumber(w) end
    walkSpeed = math.Clamp(walkSpeed, speeds.Min or 80, speeds.Max or 400)
    runSpeed = math.Clamp(runSpeed, walkSpeed, speeds.Max or 400)
    local dist = math.sqrt(math.max(distSqr or 0, 0))
    if dist > (nav.FastDist or 150) then
        return runSpeed, true
    else
        return walkSpeed, false
    end
end
local function CheckStrafeClearance(bot, moveDir, sideDir)
    if not IsValid(bot) then return false, false, false end
    local clearance = AI_CONFIG.Magic.Navigation.StrafeWallClearance or 24
    local botPos = bot:GetPos()
    local rightTr = util.TraceHull({
        start = botPos + Vector(0, 0, 20),
        endpos = botPos + Vector(0, 0, 20) + sideDir * clearance,
        mins = Vector(-12, -12, 0), maxs = Vector(12, 12, 20),
        filter = bot, mask = MASK_PLAYERSOLID
    })
    local leftTr = util.TraceHull({
        start = botPos + Vector(0, 0, 20),
        endpos = botPos + Vector(0, 0, 20) + (-sideDir) * clearance,
        mins = Vector(-12, -12, 0), maxs = Vector(12, 12, 20),
        filter = bot, mask = MASK_PLAYERSOLID
    })
    local fwdTr = util.TraceHull({
        start = botPos + Vector(0, 0, 20),
        endpos = botPos + Vector(0, 0, 20) + moveDir * 40,
        mins = Vector(-12, -12, 0), maxs = Vector(12, 12, 20),
        filter = bot, mask = MASK_PLAYERSOLID
    })
    local canRight = not rightTr.Hit
    local canLeft = not leftTr.Hit
    local canForward = not fwdTr.Hit
    local isNarrow = (not canRight) and (not canLeft) and (not canForward)
    return canRight, canLeft, isNarrow
end
local function ApplySmartMovement(bot, cmd, moveDir, speed, wantSprint, lookAng, st)
    if not IsValid(bot) or not cmd then return end
    cmd:SetViewAngles(lookAng)
    bot:SetEyeAngles(lookAng)
    if wantSprint then AddCmdButton(cmd, IN_SPEED) else RemoveCmdButton(cmd, IN_SPEED) end
    local viewAng = cmd:GetViewAngles()
    local fwd = viewAng:Forward()
    fwd.z = 0
    fwd:Normalize()
    local rgt = viewAng:Right()
    rgt.z = 0
    rgt:Normalize()
    local forwardComp = moveDir:Dot(fwd)
    local sideComp = moveDir:Dot(rgt)
    local canStrafeRight, canStrafeLeft, isNarrow = CheckStrafeClearance(bot, moveDir, rgt)
    if isNarrow then
        local backDir = -fwd
        local backTr = util.TraceHull({
            start = bot:GetPos() + Vector(0, 0, 20),
            endpos = bot:GetPos() + Vector(0, 0, 20) + backDir * 40,
            mins = Vector(-12, -12, 0), maxs = Vector(12, 12, 20),
            filter = bot, mask = MASK_PLAYERSOLID
        })
        if not backTr.Hit then
            moveDir = backDir
        else
            cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_JUMP))
            local options = { fwd, -fwd, rgt, -rgt }
            for _, opt in ipairs(options) do
                local testTr = util.TraceHull({
                    start = bot:GetPos() + Vector(0, 0, 20),
                    endpos = bot:GetPos() + Vector(0, 0, 20) + opt * 30,
                    mins = Vector(-12, -12, 0), maxs = Vector(12, 12, 20),
                    filter = bot, mask = MASK_PLAYERSOLID
                })
                if not testTr.Hit then
                    moveDir = opt
                    break
                end
            end
        end
    else
        if sideComp > 0 and not canStrafeRight then sideComp = 0 end
        if sideComp < 0 and not canStrafeLeft then sideComp = 0 end
        moveDir = fwd * forwardComp + rgt * sideComp
        if moveDir:LengthSqr() > 0.001 then moveDir:Normalize() end
    end
    local vel = bot:GetVelocity()
    local vel2D = vel and Vector(vel.x, vel.y, 0):Length() or 0
    if isNarrow and vel2D > 40 then isNarrow = false end
    if st then st._inNarrowPassage = isNarrow end
    ApplyWorldMovement(cmd, moveDir, speed)
end
local function GetSteerPosition(botPos, wps, index)
    if not wps or #wps == 0 then return botPos end
    if index > #wps then return wps[#wps].pos end
    return wps[index].pos
end
local function FindDoorInFront(bot, direction)
    if not IsValid(bot) then return nil end
    if not direction or direction:LengthSqr() <= 1e-4 then return nil end
    local botPos = bot:GetPos()
    local offsets = { 20, 40, 60 }
    for _, z in ipairs(offsets) do
        local trace = util.TraceHull({
            start = botPos + Vector(0, 0, z),
            endpos = botPos + Vector(0, 0, z) + direction * 60,
            mins = Vector(-16, -16, -10),
            maxs = Vector(16, 16, 10),
            filter = bot,
            mask = MASK_PLAYERSOLID
        })
        if trace.Hit and IsValid(trace.Entity) then
            local ok, class = pcall(function() return trace.Entity:GetClass() end)
            local ok2, name = pcall(function() return trace.Entity:GetName() end)
            local isDoor = (ok and class and (class:find("door") or class == "func_door" or class == "prop_door_rotating"))
                or (ok2 and name and name:lower():find("door"))
            if isDoor then return trace.Entity end
        end
    end
    return nil
end
local Nav = { AreaCache = {} }
local function GetAreaByID(id)
    local cached = Nav.AreaCache[id]
    if cached ~= nil then return cached end
    local ok, area = pcall(navmesh.GetNavAreaByID, id)
    if not ok then area = nil end
    Nav.AreaCache[id] = area
    return area
end
local function GetAreaID(area)
    if not area then return nil end
    local ok, id = pcall(function() return area:GetID() end)
    if ok and id then return id end
    return nil
end
local function GetAreaCenter(area)
    if not area then return nil end
    local ok, center = pcall(function() return area:GetCenter() end)
    if ok and center and isvector(center) then return center end
    return nil
end
local function GetAreaClosest(area, pos)
    if not area or not pos then return nil end
    local ok, closest = pcall(function() return area:GetClosestPointOnArea(pos) end)
    if ok and closest then return closest end
    return nil
end
local function GetNearestArea(pos, radius)
    if not navmesh or not navmesh.IsLoaded() then return nil end
    if not pos then return nil end
    local ok, area = pcall(navmesh.GetNearestNavArea, pos, radius or 400)
    if ok and IsValid(area) then return area end
    return nil
end
local function GetAreaCorners(area)
    if not area then return nil end
    local ok, corners = pcall(function()
        return {
            area:GetCorner(0),
            area:GetCorner(1),
            area:GetCorner(2),
            area:GetCorner(3)
        }
    end)
    if ok and corners and #corners >= 3 then return corners end
    local center = GetAreaCenter(area)
    if not center then return nil end
    local ext = 32
    return {
        center + Vector(-ext, -ext, 0),
        center + Vector(ext, -ext, 0),
        center + Vector(ext, ext, 0),
        center + Vector(-ext, ext, 0)
    }
end
function GetAreaAttributes(area)
    if not IsValid(area) then return 0 end
    local ok, attrs = pcall(function() return area:GetAttributes() end)
    if ok and tonumber(attrs) then return tonumber(attrs) end
    return 0
end
function IsAreaBlocked(area)
    return bit.band(GetAreaAttributes(area), NAV_MESH_BLOCKED) ~= 0
end
function IsAreaObstacle(area)
    local attrs = GetAreaAttributes(area)
    return bit.band(attrs, NAV_MESH_AVOID) ~= 0
        or bit.band(attrs, NAV_MESH_OBSTACLE_TOP) ~= 0
        or bit.band(attrs, NAV_MESH_CLIFF) ~= 0
end
function IsAreaStairs(area)
    if not IsValid(area) then return false end
    local okAttr, attrs = pcall(function() return area:GetAttributes() end)
    if okAttr and attrs then
        if bit.band(attrs, NAV_MESH_NO_JUMP) ~= 0 then
            local okAdj, adj = pcall(function() return area:GetAdjacentAreas() end)
            if okAdj and adj and #adj >= 2 then
                local zs = {}
                for _, a in ipairs(adj) do
                    local c = GetAreaCenter(a)
                    if c then table.insert(zs, c.z) end
                end
                if #zs >= 2 then
                    table.sort(zs)
                    if math.abs(zs[#zs] - zs[1]) > 30 then
                        return true
                    end
                end
            end
        end
    end
    local okAdj, adj = pcall(function() return area:GetAdjacentAreas() end)
    if okAdj and adj and #adj == 2 then
        local c1 = GetAreaCenter(adj[1])
        local c2 = GetAreaCenter(adj[2])
        if c1 and c2 and math.abs(c1.z - c2.z) > 40 then
            return true
        end
    end
    return false
end
function GetAreaEntryPoint(toArea, fromArea)
    if not IsValid(toArea) or not IsValid(fromArea) then return nil end
    local fromCenter = GetAreaCenter(fromArea)
    if not fromCenter then return nil end
    local ok, corners = pcall(function()
        return {
            toArea:GetCorner(0),
            toArea:GetCorner(1),
            toArea:GetCorner(2),
            toArea:GetCorner(3)
        }
    end)
    local bestPoint = nil
    local bestDist = math.huge
    if ok and corners then
        for _, c in ipairs(corners) do
            local d = c:DistToSqr(fromCenter)
            if d < bestDist then
                bestDist = d
                bestPoint = c
            end
        end
    end
    if not bestPoint then
        bestPoint = GetAreaCenter(toArea)
    end
    return bestPoint
end
function GetAreaExitPoint(fromArea, toArea)
    return GetAreaEntryPoint(fromArea, toArea)
end
function GetStairsWaypoints(stairsArea, fromArea, toArea)
    if not IsValid(stairsArea) then return nil end
    local fromCenter = GetAreaCenter(fromArea)
    local toCenter = GetAreaCenter(toArea)
    if not fromCenter or not toCenter then return nil end
    local entry = GetAreaEntryPoint(stairsArea, fromArea)
    local exit = GetAreaExitPoint(stairsArea, toArea)
    if not entry or not exit then return nil end
    local stairsCenter = GetAreaCenter(stairsArea)
    local mid = (entry + exit) * 0.5
    if stairsCenter then mid.z = stairsCenter.z end
    return {
        { pos = entry, type = "stairs_entry", radius = 24 },
        { pos = mid,   type = "stairs_mid",   radius = 32 },
        { pos = exit,  type = "stairs_exit",  radius = 24 }
    }
end
function CanEnterArea(fromArea, toArea)
    if not IsValid(fromArea) or not IsValid(toArea) then return false end
    if IsAreaBlocked(toArea) then return false end
    if IsAreaObstacle(toArea) then
        local fromZ = GetAreaCenter(fromArea)
        local toZ = GetAreaCenter(toArea)
        if fromZ and toZ then
            if toZ.z > fromZ.z + 20 then return false end
        end
    end
    return true
end
local function HeapPush(heap, item)
    heap[#heap + 1] = item
    local i = #heap
    while i > 1 do
        local p = math.floor(i / 2)
        if heap[p].f <= heap[i].f then break end
        heap[p], heap[i] = heap[i], heap[p]
        i = p
    end
end
local function HeapPop(heap)
    local top = heap[1]
    local last = heap[#heap]
    heap[#heap] = nil
    if #heap > 0 then
        heap[1] = last
        local i = 1
        while true do
            local l = i * 2
            local r = l + 1
            local best = i
            if l <= #heap and heap[l].f < heap[best].f then best = l end
            if r <= #heap and heap[r].f < heap[best].f then best = r end
            if best == i then break end
            heap[i], heap[best] = heap[best], heap[i]
            i = best
        end
    end
    return top
end
local function ReconstructPath(came, id)
    local steps = {}
    while id do
        local c = came[id]
        local area = GetAreaByID(id)
        if area then table.insert(steps, { area = area }) end
        id = c and c.pid
    end
    local reversed = {}
    for i = #steps, 1, -1 do
        table.insert(reversed, steps[i])
    end
    return reversed
end
local function CanWalkDirect(from, to, filter)
    if not from or not to then return false end
    if from:DistToSqr(to) <= 1 then return true end
    local tr = util.TraceHull({
        start = from + Vector(0, 0, 36),
        endpos = to + Vector(0, 0, 36),
        mins = Vector(-14, -14, 0),
        maxs = Vector(14, 14, 48),
        filter = filter,
        mask = MASK_PLAYERSOLID
    })
    return not tr.Hit and not tr.StartSolid
end
local function GetNearestAreaSmart(pos, radius)
    if not navmesh or not navmesh.IsLoaded() then return nil end
    if not pos then return nil end
    local offsets = { 0, -10, -20, 10, 20, -30, 30, -50, 50, -80, 80 }
    local bestArea = nil
    local bestScore = math.huge
    for _, zOffset in ipairs(offsets) do
        local searchPos = pos + Vector(0, 0, zOffset)
        local ok, area = pcall(navmesh.GetNearestNavArea, searchPos, radius or 600)
        if ok and IsValid(area) then
            local center = GetAreaCenter(area)
            if center then
                local dist = pos:Distance(center)
                local zDiff = math.abs(pos.z - center.z)
                local score = dist + zDiff * 2
                if score < bestScore then
                    bestScore = score
                    bestArea = area
                end
            end
        end
    end
    return bestArea
end
local function GetNearestAreaCached(pos, radius, st)
    if not pos then return nil end
    local cache = st.areaCache
    if cache.area and IsValid(cache.area)
        and CurTime() - cache.time < 0.35
        and pos:DistToSqr(cache.pos) < 4096 then
        local center = GetAreaCenter(cache.area)
        if center and math.abs(center.z - pos.z) < 60 then
            return cache.area
        end
    end
    local area = GetNearestAreaSmart(pos, radius)
    cache.pos = Vector(pos)
    cache.area = area
    cache.time = CurTime()
    return area
end
function FindNavPath(startArea, goalArea, allowObstacles)
    if not startArea or not goalArea then return nil end
    local sid = GetAreaID(startArea)
    local gid = GetAreaID(goalArea)
    if not sid or not gid then return nil end
    if IsAreaBlocked(startArea) then return nil end
    if IsAreaBlocked(goalArea) then
        local goalCenter = GetAreaCenter(goalArea)
        if goalCenter then
            local nearestUnblocked = nil
            local bestDist = math.huge
            local allAreas = navmesh.GetAllNavAreas()
            for _, area in ipairs(allAreas) do
                if IsValid(area) and not IsAreaBlocked(area) then
                    local c = GetAreaCenter(area)
                    if c then
                        local d = goalCenter:DistToSqr(c)
                        if d < bestDist then
                            bestDist = d
                            nearestUnblocked = area
                        end
                    end
                end
            end
            if nearestUnblocked then
                local newGid = GetAreaID(nearestUnblocked)
                goalArea = nearestUnblocked
                gid = newGid
            else
                return nil
            end
        else
            return nil
        end
    end
    local startCenter = GetAreaCenter(startArea)
    local goalCenter = GetAreaCenter(goalArea)
    if not startCenter or not goalCenter then return nil end
    if sid == gid then
        return { { area = startArea } }
    end
    local open = {}
    local gScore = { [sid] = 0 }
    local came = {}
    local closed = {}
    HeapPush(open, { id = sid, g = 0, f = startCenter:Distance(goalCenter) })
    local iter = 0
    local maxIter = AI_CONFIG.Magic.Navigation.MaxIterations or 1500
    while #open > 0 and iter < maxIter do
        iter = iter + 1
        local cur = HeapPop(open)
        local cid = cur.id
        if closed[cid] then
        elseif cid == gid then
            return ReconstructPath(came, cid)
        else
            closed[cid] = true
            local area = GetAreaByID(cid)
            local center = area and GetAreaCenter(area)
            if area and IsAreaBlocked(area) then
            elseif area and center then
                local okAdj2, adj2 = pcall(function() return area:GetAdjacentAreas() end)
                if okAdj2 and adj2 then
                    for _, nb in ipairs(adj2) do
                        if IsValid(nb) then
                            local nid = GetAreaID(nb)
                            if nid and not closed[nid] then
                                if IsAreaBlocked(nb) then
                                elseif (not allowObstacles) and IsAreaObstacle(nb) and nid ~= gid then
                                elseif not CanEnterArea(area, nb) then
                                else
                                    local ncenter = GetAreaCenter(nb)
                                    if ncenter then
                                        local baseCost = center:Distance(ncenter)
                                        local zPenalty = math.abs(center.z - ncenter.z) * 0.5
                                        local ng = (gScore[cid] or 0) + baseCost + zPenalty
                                        if IsAreaObstacle(nb) then ng = ng + 3000 end
                                        if IsAreaStairs(nb) then ng = ng + 100 end
                                        if not gScore[nid] or ng < gScore[nid] then
                                            gScore[nid] = ng
                                            came[nid] = { pid = cid }
                                            HeapPush(open, {
                                                id = nid,
                                                g = ng,
                                                f = ng + ncenter:Distance(goalCenter)
                                            })
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end
local function BuildWaypoints(steps, startPos, goalPos)
    if not steps or #steps == 0 then return nil end
    if not startPos or not isvector(startPos) then return nil end
    if not goalPos or not isvector(goalPos) then return nil end
    local wps = {}
    table.insert(wps, { pos = Vector(startPos), type = "walk", radius = 48 })
    for i = 2, #steps - 1 do
        local st = steps[i]
        if st.area and IsValid(st.area) then
            local center = GetAreaCenter(st.area)
            if center and isvector(center) then
                local isObstacle = IsAreaObstacle(st.area)
                local isBlocked = IsAreaBlocked(st.area)
                local isStairs = IsAreaStairs(st.area)
                if isBlocked then
                elseif isStairs then
                    local prevArea = steps[i-1] and steps[i-1].area
                    local nextArea = steps[i+1] and steps[i+1].area
                    if prevArea and nextArea then
                        local stairsWPs = GetStairsWaypoints(st.area, prevArea, nextArea)
                        if stairsWPs then
                            for _, swp in ipairs(stairsWPs) do
                                table.insert(wps, swp)
                            end
                        else
                            table.insert(wps, { pos = Vector(center), type = "walk", area = st.area, radius = 48 })
                        end
                    else
                        table.insert(wps, { pos = Vector(center), type = "walk", area = st.area, radius = 48 })
                    end
                else
                    local wpPos = Vector(center)
                    local radius = 48
                    if isObstacle then
                        local prevArea = steps[i-1] and steps[i-1].area
                        local entryPoint = prevArea and GetAreaEntryPoint(st.area, prevArea)
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
                                if CanWalkDirect(prevPos, shelfPos, nil) then
                                    table.insert(wps, { pos = shelfPos, type = "walk", radius = 48 })
                                end
                            end
                        end
                    end
                    table.insert(wps, { pos = wpPos, type = "walk", area = st.area, radius = radius })
                end
            end
        end
    end
    local goalArea = GetNearestArea(goalPos, 200)
    if IsValid(goalArea) then
        local snapped = GetAreaClosest(goalArea, goalPos)
        if snapped and isvector(snapped) and math.abs(snapped.z - goalPos.z) < 40 then
            table.insert(wps, { pos = snapped, type = "walk", radius = 48 })
        else
            table.insert(wps, { pos = Vector(goalPos), type = "walk", radius = 48 })
        end
    else
        table.insert(wps, { pos = Vector(goalPos), type = "walk", radius = 48 })
    end
    return wps
end
local function GetNavState(bot)
    local botID = bot:EntIndex()
    local data = GetBotData(bot)
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
        AC.Companion.BotData[botID] = data
    end
    local st = {
        path = nav.path,
        index = nav.path_index,
        goalPos = nav.goal_pos,
        targetKey = nav.target_key,
        lastRepath = nav.repath.last_time,
        failCount = nav.fail_count,
        disabledUntil = nav.disabled_until,
        stuckPos = nav.stuck.pos,
        stuckTime = nav.stuck.time,
        unstuckDir = nav.stuck.unstuck_dir,
        unstuckUntil = nav.stuck.unstuck_until,
        forceRepath = nav.repath.force,
        nextForceRepath = nav.repath.next_force,
        doorWait = nav.door_wait,
        lastWallRepath = nav.repath.last_wall,
        repathCooldown = nav.repath.cooldown,
        wpStuckTime = nav.stuck.wp_stuck_time,
        _noProgressTime = nav.stuck.no_progress_time,
        wpStuckPos = nav.stuck.wp_stuck_pos,
        areaCache = nav.area_cache,
        _posHistory = nav.stuck.pos_history,
        _lastDistToGoal = nav.stuck.last_dist_to_goal,
        _lastDistToWP = nav.stuck.last_dist_to_wp,
        _inNarrowPassage = nav.stuck.in_narrow_passage,
        _loopKey = nav.stuck.loop_key,
        _loopCount = nav.stuck.loop_count,
        _loopReset = nav.stuck.loop_reset,
        _teleportFails = nav.stuck.teleport_fails,
        _slideTime = nav.slide_time,
    }
    return st
end
local function ShouldRepath(bot, st, targetPos, moveTarget)
    if CurTime() < st.disabledUntil then return false end
    if CurTime() < st.repathCooldown then return false end
    if st.forceRepath and CurTime() >= st.nextForceRepath then
        st.forceRepath = false
        st.repathCooldown = CurTime() + 0.3
        return true
    elseif not st.path or #st.path == 0 or st.index > #st.path then
        st.repathCooldown = CurTime() + 0.2
        return true
    else
        local key = IsValid(moveTarget) and moveTarget:EntIndex() or -1
        if st.targetKey ~= key then
            st.repathCooldown = CurTime() + 0.2
            return true
        else
            local goalMoved = st.goalPos:DistToSqr(targetPos)
            local minMove = AI_CONFIG.Magic.Navigation.MinGoalMoveForRepath or 16384
            if goalMoved > minMove * 8 then
                st.repathCooldown = CurTime() + 3.0
                return true
            elseif CurTime() - st.lastRepath > (AI_CONFIG.Magic.Navigation.RecalcInterval or 4.0)
                   and goalMoved > minMove * 3 then
                st.repathCooldown = CurTime() + 1.5
                return true
            end
        end
    end
    return false
end
local function TeleportToTarget(bot, targetPos, moveTarget, st)
    if not st then
        st = GetNavState(bot)
        if not st then return false end
    end
    st._teleportFails = st._teleportFails or 0
    if st._teleportFails > 3 then
        st._teleportFails = 0
        st.disabledUntil = CurTime() + 2.0
        return false
    end
    local back = Vector(0, 0, 0)
    if IsValid(moveTarget) then
        local ok, fwd = pcall(function() return moveTarget:GetForward() end)
        if ok and fwd then back = fwd * -80 end
    end
    local safePos = targetPos + back
    local tr = util.TraceLine({
        start = safePos + Vector(0, 0, 50),
        endpos = safePos - Vector(0, 0, 200),
        filter = IsValid(moveTarget) and moveTarget or bot,
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
        st.index = 1
        st.lastRepath = 0
        st.forceRepath = true
        st.nextForceRepath = CurTime() + 0.3
        st._teleportFails = 0
        return true
    else
        st._teleportFails = st._teleportFails + 1
    end
    return false
end
local function BuildPath(bot, st, targetPos, moveTarget)
    if not targetPos or not isvector(targetPos) then return false end
    st.lastRepath = CurTime()
    st.goalPos = Vector(targetPos)
    st.targetKey = IsValid(moveTarget) and moveTarget:EntIndex() or -1
    if CurTime() < st.disabledUntil then return false end
    if IsValid(moveTarget) and moveTarget:IsPlayer() and IsTargetNoclip(moveTarget) then
        local botPos = bot:GetPos()
        local noclipDist = botPos:DistToSqr(targetPos)
        if noclipDist < 90000 then
            if CanWalkDirect(botPos, targetPos, bot) then
                st.path = {
                    { pos = Vector(botPos), type = "walk", radius = 48 },
                    { pos = Vector(targetPos), type = "walk", radius = 48 }
                }
                st.index = 1
                return true
            end
        end
    end
    if not navmesh or not navmesh.IsLoaded() then
        st.path = nil
        return false
    end
    local botPos = bot:GetPos()
    if botPos:DistToSqr(targetPos) < (AI_CONFIG.Magic.Navigation.DirectPathDistSq or 22500) then
        st.path = {
            { pos = Vector(botPos), type = "walk", radius = 48 },
            { pos = Vector(targetPos), type = "walk", radius = 48 }
        }
        st.index = 1
        return true
    end
    local startArea = GetNearestAreaCached(botPos, 600, st)
    local goalArea = GetNearestAreaCached(targetPos, 600, st)
    if not startArea and not goalArea then
        if CanWalkDirect(botPos, targetPos, bot) then
            st.path = { { pos = Vector(botPos), type = "walk", radius = 48 }, { pos = Vector(targetPos), type = "walk", radius = 48 } }
            st.index = 1
            return true
        end
        if botPos:DistToSqr(targetPos) > (AI_CONFIG.Magic.Navigation.TeleportDist * AI_CONFIG.Magic.Navigation.TeleportDist) then
            if TeleportToTarget(bot, targetPos, moveTarget, st) then return true end
        end
        return false
    end
    if startArea and not goalArea then
        local nearestPoint = GetNearestArea(targetPos, 1500)
        if nearestPoint then goalArea = nearestPoint end
    end
    if not startArea and goalArea then
        local nearestNav = GetNearestArea(botPos, 1500)
        if nearestNav then
            local navCenter = GetAreaCenter(nearestNav)
            if navCenter and CanWalkDirect(botPos, navCenter, bot) then
                st.path = { { pos = Vector(botPos), type = "walk", radius = 48 }, { pos = navCenter, type = "walk", radius = 48 } }
                st.index = 1
                return true
            end
        end
    end
    if not startArea or not goalArea then return false end
    local steps = FindNavPath(startArea, goalArea, false)
    if not steps then
        steps = FindNavPath(startArea, goalArea, true)
    end
    if not steps then
        local altGoal = GetNearestAreaSmart(targetPos, 1500)
        if altGoal and altGoal ~= goalArea then
            local altSteps = FindNavPath(startArea, altGoal, true)
            if altSteps then
                steps = altSteps
                goalArea = altGoal
            end
        end
    end
    if not steps then
        if CanWalkDirect(botPos, targetPos, bot) then
            st.path = { { pos = Vector(botPos), type = "walk", radius = 48 }, { pos = Vector(targetPos), type = "walk", radius = 48 } }
            st.index = 1
            return true
        end
        if botPos:DistToSqr(targetPos) > (AI_CONFIG.Magic.Navigation.TeleportDist * AI_CONFIG.Magic.Navigation.TeleportDist) then
            if TeleportToTarget(bot, targetPos, moveTarget) then return true end
        end
        st.failCount = st.failCount + 1
        if st.failCount > 4 then
            st.failCount = 0
            st.disabledUntil = CurTime() + 3
        end
        st.path = nil
        return false
    end
    local raw = BuildWaypoints(steps, botPos, targetPos)
    if raw and #raw > 0 then
        if st.path and st.index > 1 and st.targetKey == (IsValid(moveTarget) and moveTarget:EntIndex() or -1) then
            local oldWP = st.path[st.index]
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
                st.index = math.max(1, closestIdx)
            else
                st.index = 1
            end
        else
            st.index = 1
        end
        st.path = raw
        st.failCount = 0
        return true
    end
end
local function ShouldJump(bot, moveDir, blocked, wallTr, nextWP)
    if not bot:IsOnGround() then return false end
    local botPos = bot:GetPos()
    local magicNav = AI_CONFIG.Magic.Navigation
    if nextWP and nextWP.type:find("stairs") then return false end
    if nextWP and nextWP.type == "drop" then
        local toWP = nextWP.pos - botPos
        if toWP:LengthSqr() > 0.001 then
            toWP:Normalize()
            local dot = moveDir:Dot(toWP)
            if dot > 0.7 then return true end
        end
    end
    if nextWP and nextWP.pos.z - botPos.z > 15 then
        local flatDist = Vector(nextWP.pos.x - botPos.x, nextWP.pos.y - botPos.y, 0):Length()
        if flatDist < 100 then return true end
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
            if height > 8 and height < 45 then
                local topCheck = util.TraceHull({
                    start = stepCheck.HitPos + Vector(0, 0, 2) + forward * 10,
                    endpos = stepCheck.HitPos + Vector(0, 0, 2) + forward * 10 + Vector(0, 0, 72),
                    mins = Vector(-16, -16, 0),
                    maxs = Vector(16, 16, 0),
                    filter = bot,
                    mask = MASK_PLAYERSOLID
                })
                if not topCheck.Hit then return true end
            end
        end
    end
    local checkPos = botPos + moveDir * (magicNav.JumpCheckDist or 32)
    local gap = util.TraceHull({
        start = checkPos + Vector(0, 0, 10),
        endpos = checkPos - Vector(0, 0, 200),
        mins = Vector(-16, -16, 0),
        maxs = Vector(16, 16, 0),
        filter = bot,
        mask = MASK_PLAYERSOLID
    })
    if not gap.Hit then return true end
    if blocked and wallTr and wallTr.Hit then
        local wallHeight = wallTr.HitPos.z - botPos.z
        if wallHeight > 0 and wallHeight < (magicNav.MaxClimbHeight or 40) then
            local topPos = wallTr.HitPos + Vector(0, 0, 2) + moveDir * 20
            local top = util.TraceHull({
                start = topPos,
                endpos = topPos + Vector(0, 0, 60),
                mins = Vector(-16, -16, 0),
                maxs = Vector(16, 16, 48),
                filter = bot,
                mask = MASK_PLAYERSOLID
            })
            if not top.Hit then return true end
        end
    end
    return false
end
local function ResolveWall(bot, moveDir, st, moveTarget)
    local botPos = bot:GetPos()
    local tr = util.TraceHull({
        start = botPos + Vector(0, 0, 15),
        endpos = botPos + Vector(0, 0, 15) + moveDir * 50,
        mins = Vector(-12, -12, 0),
        maxs = Vector(12, 12, 20),
        filter = bot,
        mask = MASK_PLAYERSOLID
    })
    if not tr.Hit or tr.StartSolid then return moveDir, false, tr end
    if IsValid(tr.Entity) and moveTarget and tr.Entity == moveTarget then return moveDir, false, tr end
    local class = ""
    if IsValid(tr.Entity) then
        local ok, c = pcall(function() return tr.Entity:GetClass() end)
        if ok and c then class = c end
    end
    if class:find("door") then return moveDir, false, tr end
    local n = tr.HitNormal
    if n.z > 0.7 then return moveDir, false, tr end
    n.z = 0
    if n:LengthSqr() < 0.001 then return moveDir, false, tr end
    n:Normalize()
    local slide = moveDir - (moveDir:Dot(n) * n)
    slide.z = 0
    if slide:LengthSqr() > 0.001 then
        slide:Normalize()
        local slideTr = util.TraceHull({
            start = botPos + Vector(0, 0, 15),
            endpos = botPos + Vector(0, 0, 15) + slide * 35,
            mins = Vector(-12, -12, 0),
            maxs = Vector(12, 12, 20),
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
                endpos = botPos + Vector(0, 0, 15) + cand * 35,
                mins = Vector(-12, -12, 0),
                maxs = Vector(12, 12, 20),
                filter = bot,
                mask = MASK_PLAYERSOLID
            })
            if not cTr.Hit then return cand, true, tr end
        end
    end
    return -moveDir, true, tr
end
local function GetAvoidanceDir(bot, moveDir, moveTarget)
    local botPos = bot:GetPos()
    local avoid = Vector(0, 0, 0)
    local nearby = ents.FindInSphere(botPos, AI_CONFIG.Magic.Navigation.AvoidanceRadius or 64) or {}
    for _, ent in ipairs(nearby) do
        if ent == bot then continue end
        if moveTarget and ent == moveTarget then continue end
        if not IsValid(ent) then continue end
        if not (ent:IsPlayer() or ent:IsNPC()) then continue end
        if ent:IsPlayer() and not ent:Alive() then continue end
        if ent:IsNPC() then
            local ok, alive = pcall(function() return ent:Alive() end)
            if ok and not alive then continue end
        end
        local diff = botPos - ent:GetPos()
        diff.z = 0
        local d = diff:Length()
        if d > 1 and d < 64 then
            diff:Normalize()
            avoid = avoid + diff * ((64 - d) / 64)
        end
    end
    if avoid:LengthSqr() < 0.01 then return moveDir end
    local candidate = (moveDir * 0.65 + avoid * 0.85)
    if candidate:LengthSqr() < 0.001 then return moveDir end
    candidate:Normalize()
    local tr = util.TraceHull({
        start = botPos + Vector(0, 0, 15),
        endpos = botPos + Vector(0, 0, 15) + candidate * 40,
        mins = Vector(-12, -12, 0),
        maxs = Vector(12, 12, 20),
        filter = bot,
        mask = MASK_PLAYERSOLID
    })
    if not tr.Hit then return candidate end
    return moveDir
end
local function HandleDoor(bot, cmd, moveDir, st)
    local door = FindDoorInFront(bot, moveDir)
    if not IsValid(door) then
        st.doorWait = 0
        return false
    end
    door._aiDoorTries = door._aiDoorTries or 0
    local botPos = bot:GetPos()
    local tr = util.TraceHull({
        start = botPos + Vector(0, 0, 20),
        endpos = botPos + Vector(0, 0, 20) + moveDir * 50,
        mins = Vector(-12, -12, 0), maxs = Vector(12, 12, 20),
        filter = bot, mask = MASK_PLAYERSOLID
    })
    if not (tr.Hit and tr.Entity == door) then
        door._aiDoorTries = 0
        st.doorWait = 0
        return false
    end
    if door._aiDoorTries >= 3 then return false end
    door._aiDoorTries = door._aiDoorTries + 1
    door:Fire("Unlock", "", 0)
    door:Fire("Open", "", 0)
    door:Fire("Toggle", "", 0.15)
    local okSeq, seqs = pcall(function() return door:GetSequenceList() end)
    if okSeq and seqs then
        for _, s in ipairs(seqs) do
            if s:lower():find("open") or s:lower():find("slide") then
                door:Fire("SetAnimation", s, 0.2)
                break
            end
        end
    end
    st.doorWait = CurTime() + 0.7
    local ang = moveDir:Angle()
    ang.p = 0; ang.r = 0
    cmd:SetViewAngles(ang)
    bot:SetEyeAngles(ang)
    cmd:SetForwardMove(0)
    cmd:SetSideMove(0)
    return true
end
local function ShouldCrouch(bot, moveDir, moveTarget)
    local botID = bot:EntIndex()
    local data = GetBotData(bot)
    if data and data.navigation and data.navigation.path and data.navigation.path[data.navigation.path_index] then
        local wp = data.navigation.path[data.navigation.path_index]
        if wp.type and wp.type:find("stairs") then return false end
    end
    local stealthMode = bot:GetNWBool("AI_StealthMode", false)
    if stealthMode and bot._aiStealthCrouch then return true end
    local botPos = bot:GetPos()
    local dir = Vector(moveDir.x, moveDir.y, 0)
    if dir:LengthSqr() < 0.001 then dir = bot:GetForward() end
    dir.z = 0
    if dir:LengthSqr() < 0.001 then dir = Vector(1, 0, 0) end
    dir:Normalize()
    local tr = util.TraceHull({
        start = botPos + Vector(0, 0, 18),
        endpos = botPos + Vector(0, 0, 18) + dir * 30,
        mins = Vector(-14, -14, 0),
        maxs = Vector(14, 14, 52),
        filter = function(ent)
            if not IsValid(ent) then return false end
            if ent == bot then return false end
            if IsValid(moveTarget) and ent == moveTarget then return false end
            if ent.IsPlayer and ent:IsPlayer() then return false end
            if ent.IsNPC and ent:IsNPC() then return false end
            return true
        end,
        mask = MASK_PLAYERSOLID
    })
    return tr.Hit and not tr.StartSolid
end
local function AdvanceWaypoints(bot, st)
    local botPos = bot:GetPos()
    if st.path and st.index == 1 and #st.path > 1 then
        local wp1 = st.path[1]
        if wp1 and wp1.type == "walk" then
            local d = wp1.pos:DistToSqr(botPos)
            if d < (wp1.radius or 48) * (wp1.radius or 48) then
                st.index = 2
                if st.path[2] then
                    st.path[2]._enterTime = nil
                    st.path[2]._enterPos = nil
                    st.path[2]._bestDist = nil
                end
            end
        end
    end
    local guard = 0
    while st.path and st.index <= #st.path and guard < 12 do
        guard = guard + 1
        local wp = st.path[st.index]
        if not wp then break end
        local to = wp.pos - botPos
        local dist = to:Length()
        local radius = wp.radius or 80
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
            elseif timeOnWP > 3.0 and movedOnWP < 100 then
                shouldSkip = true
            end
        elseif wp.type == "drop" then
            if botPos.z < wp.pos.z - 15 then
                shouldSkip = true
            elseif flatDist < radius then
                shouldSkip = true
            elseif timeOnWP > 4.0 and movedOnWP < 16 then
                shouldSkip = true
            end
        else
            if dist < radius then
                shouldSkip = true
            elseif flatDist < radius * 0.7 and heightDiff < 50 then
                shouldSkip = true
            elseif timeOnWP > 4.0 and movedOnWP < 16 then
                shouldSkip = true
            elseif heightDiff > 80 and flatDist < radius * 0.5 and timeOnWP > 3.0 then
                shouldSkip = true
            end
        end
        if shouldSkip then
            st.index = st.index + 1
            if st.path[st.index] then
                st.path[st.index]._enterTime = nil
                st.path[st.index]._enterPos = nil
                st.path[st.index]._bestDist = nil
            end
        else
            break
        end
    end
    if st.path and st.index > #st.path then st.path = nil end
end
local function MoveDirect(bot, cmd, targetPos, moveTarget, st)
    if not IsValid(bot) or not cmd then return end
    local targetIsNoclip = IsValid(moveTarget) and moveTarget:IsPlayer() and IsTargetNoclip(moveTarget)
    if targetIsNoclip then
        ClearDuckFlags(bot)
        cmd:SetButtons(bit.band(cmd:GetButtons(), bit.bnot(IN_DUCK)))
    end
    local botPos = bot:GetPos()
    local dir = targetPos - botPos
    dir.z = 0
    if dir:LengthSqr() <= 1 then return end
    dir:Normalize()
    local blocked, wallTr
    dir, blocked, wallTr = ResolveWall(bot, dir, st, moveTarget)
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
    if HandleDoor(bot, cmd, dir, st) then return end
    local jump = ShouldJump(bot, dir, blocked, wallTr, nil)
    local crouch = (not targetIsNoclip) and (ShouldCrouch(bot, dir, moveTarget) or (bot._aiStealthCrouch == true))
    local speed, wantSprint = GetBotMoveSpeed(bot, botPos:DistToSqr(targetPos), crouch)
    local lookAng = GetLookAngle(bot, moveTarget or targetPos)
    ApplySmartMovement(bot, cmd, dir, speed, wantSprint, lookAng, st)
    local btns = cmd:GetButtons()
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
end
local function RegisterPathFailure(bot, st, botPos, wpPos)
    local bArea = GetNearestAreaSmart(botPos, 300)
    local wArea = GetNearestAreaSmart(wpPos or st.goalPos, 300)
    local bid = bArea and GetAreaID(bArea) or nil
    local wid = wArea and GetAreaID(wArea) or nil
    local gArea = GetNearestAreaSmart(st.goalPos, 400)
    local gid = gArea and GetAreaID(gArea) or 0
    local key = (bid or 0) .. ">" .. gid
    local now = CurTime()
    if st._loopKey == key and now - (st._loopReset or 0) < 25 then
        st._loopCount = (st._loopCount or 0) + 1
    else
        st._loopKey = key
        st._loopCount = 1
        st._loopReset = now
    end
    if st._loopCount >= 4 then
        st._loopCount = 0
        local gc = gArea and GetAreaCenter(gArea)
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
local function UpdateStuck(bot, cmd, moveDir, st)
    if CurTime() < st.unstuckUntil and st.unstuckDir then
        ApplyWorldMovement(cmd, st.unstuckDir, 220)
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
                    st.index = 1
                    st.stuckTime = 0
                    st._lastDistToWP = nil
                    st._lastDistToGoal = nil
                    return false
                end
            end
        end
    end
    st._posHistory = st._posHistory or {}
    st._lastDistToGoal = st._lastDistToGoal or nil
    st._lastDistToWP = st._lastDistToWP or nil
    local wantsMove = moveDir:LengthSqr() > 0.001
        or cmd:GetForwardMove() ~= 0
        or cmd:GetSideMove() ~= 0
    if not wantsMove then
        st.stuckTime = 0
        st.stuckPos = botPos
        st._posHistory = {}
        st._lastDistToWP = nil
        st._lastDistToGoal = nil
        return false
    end
    table.insert(st._posHistory, { pos = Vector(botPos), time = now })
    while #st._posHistory > 0 and (now - st._posHistory[1].time) > 2.5 do
        table.remove(st._posHistory, 1)
    end
    local wp = st.path and st.path[st.index]
    local distToWP = math.huge
    if wp then
        local toWP = wp.pos - botPos
        toWP.z = 0
        distToWP = toWP:Length()
        if st._lastDistToWP and distToWP < st._lastDistToWP - 2 then
            st.stuckTime = 0
            st.stuckPos = botPos
            st._lastDistToWP = distToWP
            return false
        end
        local wpRadius = (wp and wp.radius) or 48
        if st._lastDistToWP and math.abs(distToWP - st._lastDistToWP) < 2
            and distToWP > wpRadius + 10 then
            st._noProgressTime = (st._noProgressTime or 0) + FrameTime()
            if st._noProgressTime > 3.0 then
                st._noProgressTime = 0
                if st.index < #st.path then
                    local nextWP = st.path[st.index + 1]
                    if nextWP then
                        local toNext = nextWP.pos - botPos
                        toNext.z = 0
                        local nextDist = toNext:Length()
                        if nextDist > 200 then
                            local canReach = CanWalkDirect(botPos + Vector(0,0,36), nextWP.pos + Vector(0,0,36), bot)
                            if not canReach then
                                RegisterPathFailure(bot, st, botPos, nextWP.pos)
                                st.path = nil
                                st.index = 1
                                st.forceRepath = true
                                st.nextForceRepath = CurTime() + 0.5
                                return false
                            end
                        end
                    end
                    st.index = st.index + 1
                    st.stuckTime = 0
                    st._posHistory = {}
                    st._lastDistToWP = nil
                    return false
                else
                    RegisterPathFailure(bot, st, botPos, wp and wp.pos or st.goalPos)
                    st.path = nil
                    st.index = 1
                    st.forceRepath = true
                    st.nextForceRepath = CurTime() + 0.5
                    return false
                end
            end
        else
            st._noProgressTime = 0
        end
        st._lastDistToWP = distToWP
    end
    local goalPos = st.goalPos
    local distToGoal = goalPos and botPos:DistToSqr(goalPos) or math.huge
    if st._lastDistToGoal and distToGoal < st._lastDistToGoal - 100 then
        st.stuckTime = 0
        st.stuckPos = botPos
        st._lastDistToGoal = distToGoal
        return false
    end
    st._lastDistToGoal = distToGoal
    local vel = bot:GetVelocity()
    local speed2D = vel and Vector(vel.x, vel.y, 0):Length() or 0
    local isStuck = false
    if #st._posHistory >= 3 then
        local firstPos = st._posHistory[1].pos
        local timeSpan = now - st._posHistory[1].time
        if timeSpan >= 1.5 then
            local netDisplacement = botPos:Distance(firstPos)
            if netDisplacement < 8 and speed2D < 20 then
                isStuck = true
            end
        end
    end
    if not isStuck then
        st.stuckTime = 0
        st.stuckPos = botPos
        return false
    end
    st.stuckTime = st.stuckTime + math.max(FrameTime(), 0.001)
    if st.stuckTime > (AI_CONFIG.Magic.Navigation.UnstuckTime or 1.5) then
        if st.path and st.index < #st.path then
            local nextWP = st.path[st.index + 1]
            st.index = st.index + 1
            st.stuckTime = 0
            st.stuckPos = botPos
            st._posHistory = {}
            st._lastDistToWP = nil
            st._noProgressTime = 0
            if nextWP then
                local pushDir = nextWP.pos - botPos
                pushDir.z = 0
                if pushDir:LengthSqr() > 0.001 then
                    pushDir:Normalize()
                    st.unstuckDir = pushDir
                    st.unstuckUntil = CurTime() + (AI_CONFIG.Magic.Navigation.UnstuckDuration or 1.0)
                    ApplyWorldMovement(cmd, pushDir, 300)
                    cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_JUMP))
                    return true
                end
            end
            return false
        end
        st.stuckTime = 0
        st.stuckPos = botPos
        st._posHistory = {}
        st._noProgressTime = 0
        st.forceRepath = true
        st.nextForceRepath = CurTime() + 0.3
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
        st.unstuckDir = chosen
        st.unstuckUntil = CurTime() + (AI_CONFIG.Magic.Navigation.UnstuckDuration or 1.0)
        cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_JUMP))
        ApplyWorldMovement(cmd, chosen, 220)
        return true
    end
    return false
end
local function UpdateNavigation(bot, cmd, targetPos, moveTarget)
    local st = GetNavState(bot)
    if not st then return end
    local botPos = bot:GetPos()
    local targetIsNoclip = IsValid(moveTarget) and moveTarget:IsPlayer() and IsTargetNoclip(moveTarget)
    local distToTarget
    if targetIsNoclip then
        local dx, dy = targetPos.x - botPos.x, targetPos.y - botPos.y
        distToTarget = dx * dx + dy * dy
    else
        distToTarget = botPos:DistToSqr(targetPos)
    end
    if distToTarget < (AI_CONFIG.Magic.Navigation.CloseFollowDistSq or 3600) then
        cmd:ClearMovement()
        cmd:ClearButtons()
        st.path = nil
        st.index = 1
        st.stuckTime = 0
        local lookAng = GetLookAngle(bot, moveTarget or targetPos)
        cmd:SetViewAngles(lookAng)
        bot:SetEyeAngles(lookAng)
        return
    end
    local onGround = bot:IsOnGround()
    local zDiff = math.abs(targetPos.z - botPos.z)
    local directPathMax = AI_CONFIG.Magic.Navigation.DirectPathMaxDistSq or 160000
    if distToTarget < directPathMax then
        local canDirect = false
        if distToTarget < (AI_CONFIG.Magic.Navigation.DirectPathDistSq or 10000) then
            canDirect = true
        elseif st.path and #st.path > 0 and st.index <= #st.path and st.index > 1 then
            canDirect = false
        else
            local trace = util.TraceHull({
                start = botPos + Vector(0, 0, 36),
                endpos = targetPos + Vector(0, 0, 36),
                mins = Vector(-14, -14, 0),
                maxs = Vector(14, 14, 48),
                filter = bot,
                mask = MASK_PLAYERSOLID
            })
            canDirect = not trace.Hit and not trace.StartSolid
        end
        if canDirect then
            MoveDirect(bot, cmd, targetPos, moveTarget, st)
            return
        end
    end
    if not navmesh or not navmesh.IsLoaded() then
        MoveDirect(bot, cmd, targetPos, moveTarget, st)
        return
    end
    if ShouldRepath(bot, st, targetPos, moveTarget) then
        local ok = BuildPath(bot, st, targetPos, moveTarget)
        if not ok then
            MoveDirect(bot, cmd, targetPos, moveTarget, st)
            return
        end
    end
    if not st.path or #st.path == 0 then
        MoveDirect(bot, cmd, targetPos, moveTarget, st)
        return
    end
    AdvanceWaypoints(bot, st)
    local wp = st.path and st.path[st.index]
    if not wp then
        MoveDirect(bot, cmd, targetPos, moveTarget, st)
        return
    end
    local steerPos = GetSteerPosition(botPos, st.path, st.index)
    local moveDir = steerPos - botPos
    local heightDiff2 = math.abs(moveDir.z)
    if heightDiff2 > 20 then
        moveDir.z = math.Clamp(moveDir.z, -100, 100)
    else
        moveDir.z = 0
    end
    if moveDir:LengthSqr() < 0.001 then
        moveDir = targetPos - botPos
        moveDir.z = 0
    end
    moveDir:Normalize()
    moveDir = GetAvoidanceDir(bot, moveDir, moveTarget)
    local blocked, wallTr
    moveDir, blocked, wallTr = ResolveWall(bot, moveDir, st, moveTarget)
    if blocked and bot:IsOnGround() then
        local ent = wallTr and wallTr.Entity
        local isDoor = IsValid(ent) and ((ent:GetClass() or ""):find("door") or (ent:GetName() or ""):find("door"))
        if not isDoor then
            st._slideTime = (st._slideTime or 0) + FrameTime()
            if st._slideTime > 1.5 then
                st._slideTime = 0
                local wpNow = st.path and st.path[st.index]
                if wpNow then
                    local bA = GetNearestAreaCached(botPos, 300, st)
                    local wA = wpNow.area or GetNearestAreaSmart(wpNow.pos, 300)
                    local bId = bA and GetAreaID(bA)
                    local wId = wA and GetAreaID(wA)
                    if bId and wId and bId ~= wId then
                        st.forceRepath = true
                        st.nextForceRepath = CurTime() + 0.3
                    end
                end
            end
        end
    else
        st._slideTime = 0
    end
    if HandleDoor(bot, cmd, moveDir, st) then return end
    local nextWP = st.path and st.path[st.index + 1]
    local jump = ShouldJump(bot, moveDir, blocked, wallTr, nextWP)
    local data = GetBotData(bot)
    local isCombat = data and data.combat and IsValid(data.combat.target)
    local crouch = (not isCombat) and ShouldCrouch(bot, moveDir, moveTarget) or
                   (bot._aiStealthCrouch == true)
    local isOnStairs = wp and wp.type:find("stairs")
    local speed, wantSprint = GetBotMoveSpeed(bot, botPos:DistToSqr(targetPos), crouch, isOnStairs)
    local lookAng = GetLookAngle(bot, moveTarget or targetPos)
    ApplySmartMovement(bot, cmd, moveDir, speed, wantSprint, lookAng, st)
    local btns = cmd:GetButtons()
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
    local stuckOverride = UpdateStuck(bot, cmd, moveDir, st)
    if stuckOverride then return end
end
function AI_Companion_MoveToTarget(bot, cmd, targetPos, moveTarget)
    if not IsValid(bot) or not cmd then return end
    UpdateNavigation(bot, cmd, targetPos, moveTarget)
end
local function MaintainIdleWeapon(bot, navData, isCombat)
    if isCombat then return end
    local data = GetBotData(bot)
    if not data then return end
    local medicMode = data.config and data.config.medic_mode or false
    if medicMode then
        local botID = bot:EntIndex()
        local owner = nil
		if data and data.owner then
			owner = data.owner
		end
		if not owner then
			owner = bot:GetNWEntity("AICompanionOwnerEnt")
		end
        local needHeal = false
        if IsValid(owner) and owner:Health() < owner:GetMaxHealth() * 0.7 then
            needHeal = true
        elseif bot:Health() < bot:GetMaxHealth() * 0.5 then
            needHeal = true
        end
        if needHeal and bot:HasWeapon("weapon_medkit") then return end
    end
    local desired = data.config and data.config.idle_weapon or "weapon_physgun"
    local desiredStr = tostring(desired)
    if desiredStr == "" then return end
    if not bot._lastDesiredIdleWeapon then
        bot._lastDesiredIdleWeapon = desiredStr
    end
    if bot._lastDesiredIdleWeapon ~= desiredStr then
        navData.lastWeaponSwitch = 0
        bot._lastDesiredIdleWeapon = desiredStr
        if AI_CONFIG and AI_CONFIG.DEBUG_MODE then
            print(string.format("[AI Movement] Idle weapon changed to %s, resetting switch timer", desiredStr))
        end
    end
    if not bot:HasWeapon(desiredStr) then bot:Give(desiredStr) end
    local aw = bot:GetActiveWeapon()
    if IsValid(aw) and aw:GetClass() ~= desiredStr then
        if navData.lastWeaponSwitch == 0 or CurTime() - (navData.lastWeaponSwitch or 0) > 1.0 then
            bot:SelectWeapon(desiredStr)
            navData.lastWeaponSwitch = CurTime()
            if AI_CONFIG and AI_CONFIG.DEBUG_MODE then
                print(string.format("[AI Movement] Switched to idle weapon: %s", desiredStr))
            end
        end
    end
end
hook.Add("StartCommand", "AICompanion_Movement_v74", function(bot, cmd)
    local data = GetBotData(bot)
    if data and data.config then
        bot:SetNWBool("AI_StealthMode", data.config.stealth_mode or false)
        bot:SetNWBool("AI_DefenderMode", data.config.defender_mode or false)
        bot:SetNWBool("AI_MedicMode", data.config.medic_mode or false)
        bot:SetNWBool("AI_PacifistMode", data.config.pacifist_mode or false)
        bot:SetNWBool("AI_AggressiveMode", data.config.aggressive_mode or false)
    end
    if AC.State.Disabled then
        if IsValid(bot) and bot:GetNWBool("IsAICompanion", false) and bot:Alive() then
            cmd:ClearMovement()
            cmd:ClearButtons()
        end
        return
    end
    if not IsValid(bot) or not bot:Alive() then return end
    if not bot:GetNWBool("IsAICompanion", false) then return end
    if not bot:IsBot() then return end
    local botID = bot:EntIndex()
	local data = GetBotData(bot)
	local owner = nil
	local data = GetBotData(bot)
	if data and data.owner then
		owner = data.owner
	end
	if not owner then
		owner = bot:GetNWEntity("AICompanionOwnerEnt")
	end
	if not owner then
		owner = bot:GetNWEntity("AICompanionOwnerEnt")
	end
    local stealthMode = bot:GetNWBool("AI_StealthMode", false)
    local needStealthCrouch = false
    if stealthMode and IsValid(owner) and owner:IsPlayer() and owner:Alive() then
        local ok1, crouching = pcall(function() return owner:Crouching() end)
        local ok2, ducking = pcall(function() return owner:KeyDown(IN_DUCK) end)
        if (ok1 and crouching) or (ok2 and ducking) then
            needStealthCrouch = true
        end
    end
    local isInCombat = data and data.combat and IsValid(data.combat.target)
    bot._aiStealthCrouch = needStealthCrouch and not isInCombat
    local moveTarget = isInCombat and data.combat.target or owner
    if not moveTarget then
        local nearest = GetNearestHuman(bot)
        if IsValid(nearest) then moveTarget = nearest end
    end
    local targetIsNoclip = IsValid(moveTarget) and moveTarget:IsPlayer() and IsTargetNoclip(moveTarget)
    if targetIsNoclip then
        ClearDuckFlags(bot)
    end
    if not targetIsNoclip then
        if needStealthCrouch and not isInCombat then
            cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_DUCK))
            bot:AddFlags(FL_DUCKING)
            bot:AddFlags(FL_ANIMDUCKING)
        else
            if bot:Crouching() or bit.band(bot:GetFlags(), FL_DUCKING) ~= 0 then
                local pos = bot:GetPos()
                local standCheck = util.TraceHull({
                    start = pos + Vector(0, 0, 8),
                    endpos = pos + Vector(0, 0, 8),
                    mins = Vector(-16, -16, 0),
                    maxs = Vector(16, 16, 72),
                    filter = bot,
                    mask = MASK_PLAYERSOLID
                })
                if not standCheck.Hit then
                    cmd:SetButtons(bit.band(cmd:GetButtons(), bit.bnot(IN_DUCK)))
                    bot:RemoveFlags(FL_DUCKING)
                    bot:RemoveFlags(FL_ANIMDUCKING)
                else
                    cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_DUCK))
                end
            end
        end
    end
    local inVehicle = bot:InVehicle()
    if inVehicle then
        local st = GetNavState(bot)
        if st then
            st.path = nil
            st.index = 1
        end
        cmd:ClearMovement()
        if ControlVehicle then
            local ok, veh = pcall(function() return bot:GetVehicle() end)
            if ok and IsValid(veh) then
                pcall(function() ControlVehicle(bot, veh, owner, cmd) end)
            end
        end
        return
    end
    if IsValid(owner) and owner:InVehicle() and not bot:InVehicle() and not isInCombat then
        local ownerVeh = nil
        pcall(function() ownerVeh = owner:GetVehicle() end)
        if IsValid(ownerVeh) then
            local root = nil
            if GetGlideRoot then
                root = GetGlideRoot(ownerVeh) or ownerVeh
            else
                root = ownerVeh
            end
            if IsValid(root) then
                local driverSeat = nil
                if GetDriverSeat then
                    driverSeat = GetDriverSeat(root)
                end
                if IsValid(driverSeat) then
                    local driver = nil
                    pcall(function() driver = driverSeat:GetDriver() end)
                    if not IsValid(driver) then
                        pcall(function() bot:EnterVehicle(driverSeat) end)
                        if bot:InVehicle() then
                            if data then
                                data.vehicle.locked_vehicle = root
                                data.vehicle.locked_seat = driverSeat
                                data.vehicle.is_driver = true
                                data.vehicle.sit_by_command = false
                            end
                            if bot.ChatPrint then
                                bot:ChatPrint("[AI] Сажусь за руль!")
                            end
                        end
                    end
                end
            end
        end
    end
	local botState = GetBotState(bot)
	local isPointing = (botState == AC.Companion.States.POINTING)
	local isIdle = (botState == AC.Companion.States.IDLE)
	if isIdle and not isInCombat then
		cmd:ClearMovement()
		cmd:ClearButtons()
		local lookTarget = owner or moveTarget or bot
		local lookAng = GetLookAngle(bot, lookTarget)
		cmd:SetViewAngles(lookAng)
		bot:SetEyeAngles(lookAng)
		return
	end
	if isPointing then
		cmd:ClearMovement()
		cmd:ClearButtons()
		local data = GetBotData(bot)
		if data and data.point and data.point.angle then
			cmd:SetViewAngles(data.point.angle)
			bot:SetEyeAngles(data.point.angle)
		else
			local lookTarget = owner or moveTarget or bot
			local lookAng = GetLookAngle(bot, lookTarget)
			cmd:SetViewAngles(lookAng)
			bot:SetEyeAngles(lookAng)
		end
		return
	end
    if not moveTarget then
        cmd:ClearMovement()
        cmd:ClearButtons()
        local nearest = GetNearestHuman(bot)
        if IsValid(nearest) then
            local lookAng = GetLookAngle(bot, nearest)
            cmd:SetViewAngles(lookAng)
            bot:SetEyeAngles(lookAng)
        end
        return
    end
    local targetPos = GetTargetPos(moveTarget, bot) or bot:GetPos()
    local botPos = bot:GetPos()
    local distToTarget
    if targetIsNoclip then
        local dx = targetPos.x - botPos.x
        local dy = targetPos.y - botPos.y
        distToTarget = dx * dx + dy * dy
    else
        distToTarget = botPos:DistToSqr(targetPos)
    end
    MaintainIdleWeapon(bot, {}, isInCombat)
    if isInCombat and HandleCombat then
        local handled = HandleCombat(bot, cmd)
        if handled then
            local btns = cmd:GetButtons()
            cmd:SetButtons(bit.band(btns, bit.bnot(IN_DUCK)))
            bot:RemoveFlags(FL_DUCKING)
            bot:RemoveFlags(FL_ANIMDUCKING)
            bot._aiStealthCrouch = false
            return
        end
        local data2 = GetBotData(bot)
        if data2 and data2.combat and IsValid(data2.combat.target) then
            local btns = cmd:GetButtons()
            cmd:SetButtons(bit.band(btns, bit.bnot(IN_DUCK)))
            bot:RemoveFlags(FL_DUCKING)
            bot:RemoveFlags(FL_ANIMDUCKING)
            bot._aiStealthCrouch = false
            return
        end
        moveTarget = owner
        if not moveTarget then
            cmd:ClearMovement()
            cmd:ClearButtons()
            return
        end
        targetPos = GetTargetPos(moveTarget, bot) or botPos
        distToTarget = botPos:DistToSqr(targetPos)
    end
    if IsValid(moveTarget) and distToTarget > (AI_CONFIG.Magic.Navigation.TeleportDist * AI_CONFIG.Magic.Navigation.TeleportDist) then
        if targetIsNoclip then
            local realDist = botPos:DistToSqr(moveTarget:GetPos())
            if realDist > (AI_CONFIG.Magic.Navigation.TeleportDist * AI_CONFIG.Magic.Navigation.TeleportDist) then
                if TeleportToTarget(bot, targetPos, moveTarget, st) then return end
            end
        else
            if TeleportToTarget(bot, targetPos, moveTarget, st) then return end
        end
    end
    UpdateNavigation(bot, cmd, targetPos, moveTarget)
end)
hook.Add("PlayerSpawn", "AICompanion_ResetSpawnTimer_v7", function(ply)
    if ply:GetNWBool("IsAICompanion", false) then
        ply._aiSpawnTime = CurTime()
        timer.Simple(0, function()
            if IsValid(ply) then
                ply:RemoveFlags(FL_ANIMDUCKING)
                ply:RemoveFlags(FL_DUCKING)
                pcall(function() ply:ConCommand("-duck") end)
            end
        end)
        timer.Simple(0.1, function()
            if IsValid(ply) then
                ply:RemoveFlags(FL_ANIMDUCKING)
                ply:RemoveFlags(FL_DUCKING)
            end
        end)
        timer.Simple(0.5, function()
            if IsValid(ply) then
                ply:RemoveFlags(FL_ANIMDUCKING)
                ply:RemoveFlags(FL_DUCKING)
            end
        end)
    end
end)
_G.GetTargetPos = GetTargetPos
_G.GetLookAngle = GetLookAngle
_G.GetAreaAttributes = GetAreaAttributes
_G.IsAreaBlocked = IsAreaBlocked
_G.IsAreaObstacle = IsAreaObstacle
_G.IsAreaStairs = IsAreaStairs
_G.GetAreaEntryPoint = GetAreaEntryPoint
_G.GetAreaExitPoint = GetAreaExitPoint
_G.GetStairsWaypoints = GetStairsWaypoints
_G.CanEnterArea = CanEnterArea
_G.IsTargetNoclip = IsTargetNoclip
_G.GetNoclipFollowPos = GetNoclipFollowPos
_G.AI_Companion_MoveToTarget = AI_Companion_MoveToTarget
print("[AI Movement] Загружена (использует AI_CONFIG.Magic)")