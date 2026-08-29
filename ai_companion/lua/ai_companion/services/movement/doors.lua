
local Doors = {}

function Doors:new(utils, constants)
    local obj = {
        utils = utils,
        constants = constants,
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function Doors:IsValid(ent)
    return self.utils and self.utils:IsValid(ent)
end

function Doors:GetConst()
    return self.constants and self.constants:get() or {}
end

function Doors:FindDoorInFront(bot, direction)
    if not self:IsValid(bot) then return nil end
    if not direction or direction:LengthSqr() <= 1e-4 then return nil end
    local const = self:GetConst()
    local botPos = bot:GetPos()

    for _, z in ipairs(const.doorOffsets) do
        local trace = util.TraceHull({
            start = botPos + Vector(0, 0, z),
            endpos = botPos + Vector(0, 0, z) + direction * 60,
            mins = Vector(-16, -16, -10),
            maxs = Vector(16, 16, 10),
            filter = bot,
            mask = MASK_PLAYERSOLID
        })
        if trace.Hit and self:IsValid(trace.Entity) then
            local ok, class = pcall(function() return trace.Entity:GetClass() end)
            local ok2, name = pcall(function() return trace.Entity:GetName() end)
            local isDoor = (ok and class and (class:find("door") or class == "func_door" or class == "prop_door_rotating"))
                or (ok2 and name and name:lower():find("door"))
            if isDoor then return trace.Entity end
        end
    end
    return nil
end

function Doors:HandleDoor(bot, cmd, moveDir, st)
    if not self:IsValid(bot) or not cmd then return false end
    local const = self:GetConst()

    local door = self:FindDoorInFront(bot, moveDir)
    if not self:IsValid(door) then
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

    if door._aiDoorTries >= const.doorMaxTries then return false end

    door._aiDoorTries = door._aiDoorTries + 1
    door:Fire("Unlock", "", 0)
    door:Fire("Open", "", 0)
    door:Fire("Toggle", "", const.doorOpenAttemptDelay)

    local okSeq, seqs = pcall(function() return door:GetSequenceList() end)
    if okSeq and seqs then
        for _, s in ipairs(seqs) do
            if s:lower():find("open") or s:lower():find("slide") then
                door:Fire("SetAnimation", s, const.doorOpenAttemptDelay)
                break
            end
        end
    end

    st.doorWait = CurTime() + const.doorOpenDelay
    local ang = moveDir:Angle()
    ang.p = 0; ang.r = 0
    cmd:SetViewAngles(ang)
    bot:SetEyeAngles(ang)
    cmd:SetForwardMove(0)
    cmd:SetSideMove(0)
    return true
end

return Doors
