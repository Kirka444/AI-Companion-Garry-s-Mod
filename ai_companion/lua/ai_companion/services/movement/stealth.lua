
local Stealth = {}

function Stealth:new(utils, constants)
    local obj = {
        utils = utils,
        constants = constants,
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function Stealth:IsValid(ent)
    return self.utils and self.utils:IsValid(ent)
end

function Stealth:GetConst()
    return self.constants and self.constants:get() or {}
end

function Stealth:ShouldCrouch(bot, owner, isInCombat)
    if not self:IsValid(bot) or not self:IsValid(owner) then return false end
    if isInCombat then return false end

    local data = self.data and self.data:GetBotData(bot)
    local stealthMode = data and data.config and data.config.stealth_mode or false
    if not stealthMode then
        stealthMode = bot:GetNWBool("AI_StealthMode", false)
    end

    if not stealthMode then
        return false
    end

    local ok1, crouching = pcall(function() return owner:Crouching() end)
    local ok2, ducking = pcall(function() return owner:KeyDown(IN_DUCK) end)

    return (ok1 and crouching) or (ok2 and ducking)
end

function Stealth:GetSpeed(bot, defaultSpeed)
    if not self:IsValid(bot) then return defaultSpeed or 200 end

    local data = self.data and self.data:GetBotData(bot)
    local stealthMode = data and data.config and data.config.stealth_mode or false
    if not stealthMode then
        stealthMode = bot:GetNWBool("AI_StealthMode", false)
    end

    if not stealthMode then
        return defaultSpeed or 200
    end

    local const = self:GetConst()
    return const.stealthSpeed or 80
end

function Stealth:Apply(bot, cmd, owner, isInCombat)
    if not self:IsValid(bot) or not self:IsValid(owner) then return false end
    if isInCombat then return false end

    local data = self.data and self.data:GetBotData(bot)
    local stealthMode = data and data.config and data.config.stealth_mode or false
    if not stealthMode then
        stealthMode = bot:GetNWBool("AI_StealthMode", false)
    end

    if not stealthMode then

        if bot._aiStealthCrouch then
            bot._aiStealthCrouch = false
            cmd:SetButtons(bit.band(cmd:GetButtons(), bit.bnot(IN_DUCK)))
            bot:RemoveFlags(FL_DUCKING)
            bot:RemoveFlags(FL_ANIMDUCKING)
        end
        return false
    end

    local shouldCrouch = self:ShouldCrouch(bot, owner, isInCombat)

    if shouldCrouch then

        if not bot._aiStealthCrouch then
            bot._aiStealthCrouch = true
        end

        local const = self:GetConst()
        local speed = const.stealthSpeed or 80

        cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_DUCK))
        bot:AddFlags(FL_DUCKING)
        bot:AddFlags(FL_ANIMDUCKING)

        return true, speed
    else

        if bot._aiStealthCrouch then
            bot._aiStealthCrouch = false
        end

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
        end

        return false
    end
end

function Stealth:IsActive(bot)
    if not self:IsValid(bot) then return false end
    return bot._aiStealthCrouch == true or bot:GetNWBool("AI_StealthMode", false)
end

function Stealth:GetState(bot)
    if not self:IsValid(bot) then
        return { active = false, crouching = false, speed = 0 }
    end

    local data = self.data and self.data:GetBotData(bot)
    local stealthMode = data and data.config and data.config.stealth_mode or false
    if not stealthMode then
        stealthMode = bot:GetNWBool("AI_StealthMode", false)
    end

    local const = self:GetConst()

    return {
        active = stealthMode,
        crouching = bot._aiStealthCrouch == true,
        speed = stealthMode and const.stealthSpeed or 0,
    }
end

function Stealth:SetEnabled(bot, enable)
    if not self:IsValid(bot) then return end

    local data = self.data and self.data:GetBotData(bot)
    if not data or not data.config then return end

    data.config.stealth_mode = enable
    bot:SetNWBool("AI_StealthMode", enable)

    if not enable then
        bot._aiStealthCrouch = false
        bot:RemoveFlags(FL_DUCKING)
        bot:RemoveFlags(FL_ANIMDUCKING)
    end

    if self.data then
        self.data:SetBotData(bot, data)
    end
end

return Stealth
