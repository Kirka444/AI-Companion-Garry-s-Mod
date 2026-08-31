
local Utils = {}

function Utils:new(utils)
    local obj = {
        utils = utils,
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function Utils:IsValid(ent)
    return self.utils and self.utils:IsValid(ent) or (ent and ent.IsValid and ent:IsValid())
end

function Utils:IsVectorValue(v)
    return type(v) == "Vector" or (type(v) == "table" and v.x and v.y and v.z)
end

function Utils:IsTargetNoclip(target)
    if not self:IsValid(target) then return false end
    if not target:IsPlayer() then return false end
    local ok, moveType = pcall(function() return target:GetMoveType() end)
    return ok and moveType == MOVETYPE_NOCLIP
end

function Utils:ClearDuckFlags(bot)
    if not self:IsValid(bot) then return end
    bot:RemoveFlags(FL_DUCKING)
    bot:RemoveFlags(FL_ANIMDUCKING)
    bot._aiStealthCrouch = false
end

function Utils:GetNPCSpinePos(ent)
    if not self:IsValid(ent) or not ent:IsNPC() then return nil end
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

function Utils:GetNoclipFollowPos(bot, target, const)
    if not self:IsValid(bot) or not self:IsValid(target) then return nil end
    local botPos = bot:GetPos()
    local targetPos = target:GetPos()
    local zDiff = math.abs(targetPos.z - botPos.z)
    if zDiff < const.noclipHeightThreshold then
        return targetPos
    end
    return Vector(targetPos.x, targetPos.y, botPos.z)
end

function Utils:GetTargetPos(target, bot, const)
    if not target then return nil end
    if self:IsVectorValue(target) then
        return Vector(target.x, target.y, target.z)
    end
    if self:IsValid(target) then
        if bot and target:IsPlayer() and self:IsTargetNoclip(target) then
            local noclipPos = self:GetNoclipFollowPos(bot, target, const)
            if noclipPos then return noclipPos end
        end
        if target:IsPlayer() then
            local ok, pos = pcall(function() return target:EyePos() end)
            if ok and pos then return pos end
        elseif target:IsNPC() then
            local spine = self:GetNPCSpinePos(target)
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

function Utils:GetLookAngle(bot, target)
    if not self:IsValid(bot) then return Angle(0, 0, 0) end
    local lookPos = nil
    if self:IsVectorValue(target) then
        lookPos = Vector(target.x, target.y, target.z)
    elseif self:IsValid(target) then
        if target:IsPlayer() then
            local ok, ep = pcall(function() return target:EyePos() end)
            if ok and ep then
                lookPos = ep
            else
                lookPos = target:GetPos() + Vector(0, 0, 64)
            end
        elseif target:IsNPC() then
            local spine = self:GetNPCSpinePos(target)
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

function Utils:GetNearestHuman(bot)
    if not self:IsValid(bot) then return nil end
    local botPos = bot:GetPos()
    local best = nil
    local bestDist = math.huge
    for _, ply in ipairs(player.GetHumans()) do
        if self:IsValid(ply) and ply:Alive() and not ply:IsBot() then
            local d = botPos:DistToSqr(ply:GetPos())
            if d < bestDist then
                bestDist = d
                best = ply
            end
        end
    end
    return best
end

function Utils:AddCmdButton(cmd, btn)
    if not cmd or not btn then return end
    cmd:SetButtons(bit.bor(cmd:GetButtons(), btn))
end

function Utils:RemoveCmdButton(cmd, btn)
    if not cmd or not btn then return end
    cmd:SetButtons(bit.band(cmd:GetButtons(), bit.bnot(btn)))
end

function Utils:ApplyWorldMovement(cmd, moveVec, speed)
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

return Utils
