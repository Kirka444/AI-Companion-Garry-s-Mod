if AI_COMPANION_COMBAT_LOADED_v15 then return end
AI_COMPANION_COMBAT_LOADED_v15 = true
local AC = _G.AI_COMPANION
if not AI_Utils then
    local ok, err = pcall(include, "ai_companion/ai_companion_utils.lua")
    if not ok then ErrorNoHalt("[AI Combat] ai_companion_utils.lua: " .. tostring(err) .. "\n") return end
end
if not AI_Companion then
    local ok, err = pcall(include, "ai_companion/ai_companion_core.lua")
    if not ok then ErrorNoHalt("[AI Combat] ai_companion_core.lua: " .. tostring(err) .. "\n") return end
end
if not AI_CONFIG then
    local ok, err = pcall(include, "ai_companion/ai_config.lua")
    if not ok then ErrorNoHalt("[AI Combat] ai_config.lua: " .. tostring(err) .. "\n") return end
end
if not IsBotSafe then
    function IsBotSafe(ent)
        if not IsValid(ent) then return false end
        if not ent.IsPlayer then return false end
        local ok, res = pcall(ent.IsPlayer, ent)
        if not ok or not res then return false end
        ok, res = pcall(ent.IsBot, ent)
        return ok and res
    end
end
_G.AI_Companion = _G.AI_Companion or {}
local function GetBotOwner(bot)
    if not IsValid(bot) then return nil end
    if BotManager and BotManager.GetData then
        local data = BotManager:GetData(bot)
        if data and IsValid(data.owner) then
            return data.owner
        end
    end
    local botID = bot:EntIndex()
    if AC.Companion.BotOwners and AC.Companion.BotOwners[botID] then
        return AC.Companion.BotOwners[botID]
    end
    local ownerEnt = bot:GetNWEntity("AICompanionOwnerEnt")
    if IsValid(ownerEnt) then
        return ownerEnt
    end
    return nil
end
local COMPANION_NAME = AI_CONFIG.COMPANION_NAME
local ARMORED_TARGETS = {
    ["npc_strider"] = true,
    ["npc_combinegunship"] = true,
    ["npc_helicopter"] = true,
    ["mbn_apc_manager"] = true,
}
local function SafeGetClass(ent)
    if not AI_Utils.IsValid(ent) then return "invalid" end
    local ok, class = pcall(function() return ent:GetClass() end)
    return (ok and class) or "error"
end
local function IsArmoredTarget(ent)
    if not AI_Utils.IsValid(ent) then return false end
    local class = SafeGetClass(ent)
    if ARMORED_TARGETS[class] then return true end
    if AI_CONFIG.ARMORED_TARGETS and AI_CONFIG.ARMORED_TARGETS[class] then return true end
    if ent:IsVehicle() then
        if string.find(class, "apc") or string.find(class, "tank") or
           string.find(class, "strider") or string.find(class, "gunship") or
           string.find(class, "helicopter") then return true end
    end
    return false
end
local function GetTargetAimPos(target)
    if not IsValid(target) then return Vector() end
    if target:IsPlayer() or target:IsNPC() then
        local boneNames = {
            "ValveBiped.Bip01_Spine2",
            "ValveBiped.Bip01_Spine1",
            "ValveBiped.Bip01_Head",
            "ValveBiped.Bip01_Neck",
            "ValveBiped.Bip01_Pelvis"
        }
        for _, boneName in ipairs(boneNames) do
            local bone = target:LookupBone(boneName)
            if bone then
                local pos = target:GetBonePosition(bone)
                if pos and pos:LengthSqr() > 0.01 then return pos end
            end
        end
    end
    if target:IsNPC() then
        local center = target:WorldSpaceCenter()
        if center then return center + Vector(0, 0, 40) end
        local pos = target:GetPos()
        if pos then return pos + Vector(0, 0, 64) end
    end
    if target:IsPlayer() then
        local ok, ep = pcall(function() return target:EyePos() end)
        if ok and ep then return ep end
        return target:GetPos() + Vector(0, 0, 64)
    end
    local ok, wsc = pcall(function() return target:WorldSpaceCenter() end)
    if ok and wsc then return wsc + Vector(0, 0, 30) end
    return target:GetPos() + Vector(0, 0, 32)
end
local function HasAmmoForWeapon(bot, weapon)
    if not AI_Utils.IsValid(bot) or not AI_Utils.IsValid(weapon) then return false end
    if AI_CONFIG.INFINITE_AMMO then return true end
    local clip = weapon:Clip1()
    if clip and clip > 0 then return true end
    local ammoType = weapon:GetPrimaryAmmoType()
    if ammoType and ammoType ~= -1 then
        local reserve = bot:GetAmmoCount(ammoType)
        if reserve and reserve > 0 then return true end
    end
    local ammoType2 = weapon:GetSecondaryAmmoType()
    if ammoType2 and ammoType2 ~= -1 then
        local reserve = bot:GetAmmoCount(ammoType2)
        if reserve and reserve > 0 then return true end
    end
    local maxClip = weapon:GetMaxClip1()
    local primaryAmmo = weapon:GetPrimaryAmmoType()
    if (maxClip == -1 or maxClip == 0) and (primaryAmmo == -1 or primaryAmmo == 0) then
        return true 
    end
    return false
end
local function HasAnyAmmo(bot)
    if not AI_Utils.IsValid(bot) then return false end
    if AI_CONFIG.INFINITE_AMMO then return true end
    local weapons = bot:GetWeapons()
    for _, wep in ipairs(weapons) do
        if AI_Utils.IsValid(wep) then
            local clip = wep:Clip1()
            if clip and clip > 0 then return true end
            local ammoType = wep:GetPrimaryAmmoType()
            if ammoType and ammoType ~= -1 then
                local reserve = bot:GetAmmoCount(ammoType)
                if reserve and reserve > 0 then return true end
            end
            local ammoType2 = wep:GetSecondaryAmmoType()
            if ammoType2 and ammoType2 ~= -1 then
                local reserve = bot:GetAmmoCount(ammoType2)
                if reserve and reserve > 0 then return true end
            end
        end
    end
    local activeWep = bot:GetActiveWeapon()
    if AI_Utils.IsValid(activeWep) then
        local clip = activeWep:Clip1()
        if clip and clip > 0 then return true end
        local ammoType = activeWep:GetPrimaryAmmoType()
        if ammoType and ammoType ~= -1 then
            local reserve = bot:GetAmmoCount(ammoType)
            if reserve and reserve > 0 then return true end
        end
    end
    return false
end
local function GivePrimaryAmmo(bot, wep, amount)
    if not AI_Utils.IsValid(bot) or not AI_Utils.IsValid(wep) then return end
    local ammo
    pcall(function() ammo = wep:GetPrimaryAmmoType() end)
    if not ammo or ammo == -1 then return end
    pcall(function() bot:GiveAmmo(amount, ammo, true) end)
end
local function SelectBestWeapon(bot, target, dist)
    if not AI_Utils.IsValid(bot) then return "weapon_smg1", "combat" end
    local botData = GetBotData(bot)
    if not botData then return "weapon_smg1", "combat" end
    if IsArmoredTarget(target) then
        if not bot:HasWeapon("weapon_rpg") then
            SafeGiveWeapon(bot, "weapon_rpg")
        end
        local rpg = bot:GetWeapon("weapon_rpg")
        if IsValid(rpg) then
            bot:GiveAmmo(5, "RPG_Round", true)
            if AI_CONFIG.INFINITE_AMMO or rpg:Clip1() <= 0 then
                rpg:SetClip1(1)
            end
        end
        return "weapon_rpg", "rpg"
    end
    local meleeWep = GetBotMeleeWeapon(bot)
    if not HasAnyAmmo(bot) then
        if not bot:HasWeapon(meleeWep) then
            SafeGiveWeapon(bot, meleeWep)
            if meleeWep ~= "weapon_crowbar" and meleeWep ~= "weapon_stunstick" then
                local mw = bot:GetWeapon(meleeWep)
                if AI_Utils.IsValid(mw) then
                    GivePrimaryAmmo(bot, mw, 30)
                end
            end
        end
        return meleeWep, "melee"
    end
    if dist < AI_CONFIG.Magic.Combat.MeleeDist then
        if not bot:HasWeapon(meleeWep) then
            SafeGiveWeapon(bot, meleeWep)
            if meleeWep ~= "weapon_crowbar" and meleeWep ~= "weapon_stunstick" then
                local wep = bot:GetWeapon(meleeWep)
                if AI_Utils.IsValid(wep) then
                    GivePrimaryAmmo(bot, wep, 30)
                end
            end
        end
        if bot:HasWeapon(meleeWep) then
            return meleeWep, "melee"
        end
    end
    if bot:HasWeapon("weapon_frag") then
        local lastThrow = botData.combat.frag_last_throw or 0
        if CurTime() - lastThrow >= AI_CONFIG.Magic.Combat.FragCooldown and
           dist > AI_CONFIG.Magic.Combat.FragMinDist and dist < AI_CONFIG.Magic.Combat.FragMaxDist then
            return "weapon_frag", "frag"
        end
    end
    local combatWep = GetBotCombatWeapon(bot)
    if not bot:HasWeapon(combatWep) then
        SafeGiveWeapon(bot, combatWep)
        local wep = bot:GetWeapon(combatWep)
        if AI_Utils.IsValid(wep) then
            GivePrimaryAmmo(bot, wep, 60)
            if AI_CONFIG.INFINITE_AMMO then
                wep:SetClip1(wep:GetMaxClip1() or AI.Config.Combat.DefaultClipSize or 30)
            end
        end
    end
    local combatWeapon = bot:GetWeapon(combatWep)
    if AI_Utils.IsValid(combatWeapon) then
        local hasAmmo = HasAmmoForWeapon(bot, combatWeapon)
        if not hasAmmo and not AI_CONFIG.INFINITE_AMMO then
            if not bot:HasWeapon(meleeWep) then
                SafeGiveWeapon(bot, meleeWep)
            end
            return meleeWep, "melee"
        end
    end
    return combatWep, "combat"
end
local function GetBotMode(bot, modeKey)
    if not IsValid(bot) then return false end
    local data = GetBotData(bot)
    if data and data.config then
        if modeKey == "AI_StealthMode" then return data.config.stealth_mode end
        if modeKey == "AI_DefenderMode" then return data.config.defender_mode end
        if modeKey == "AI_MedicMode" then return data.config.medic_mode end
        if modeKey == "AI_PacifistMode" then return data.config.pacifist_mode end
        if modeKey == "AI_AggressiveMode" then return data.config.aggressive_mode end
    end
    return bot:GetNWBool(modeKey, false)
end
local function IsMedicMode(bot) return GetBotMode(bot, "AI_MedicMode") end
local function IsPacifistMode(bot) return GetBotMode(bot, "AI_PacifistMode") end
local function IsDefenderMode(bot) return GetBotMode(bot, "AI_DefenderMode") end
local function IsAggressiveMode(bot) return GetBotMode(bot, "AI_AggressiveMode") end
local function SafeFindInSphere(pos, radius) return AI_Utils.FindInSphere(pos, radius) end
local function SafeGetPos(ent)
    if not AI_Utils.IsValid(ent) then return Vector() end
    local ok, pos = pcall(function() return ent:GetPos() end)
    return (ok and pos) or Vector()
end
local function SafeGetVelocity(ent)
    if not AI_Utils.IsValid(ent) then return Vector() end
    local ok, vel = pcall(function() return ent:GetVelocity() end)
    return (ok and vel) or Vector()
end
local function SafeAlive(ent)
    if not AI_Utils.IsValid(ent) then return false end
    local ok, alive = pcall(function() return ent:Alive() end)
    return ok and alive
end
local function IsValidTarget(ent)
    if not AI_Utils.IsValid(ent) then return false end
    if ent:IsWorld() then return false end
    if ent:GetClass() == "worldspawn" then return false end
    if string.find(ent:GetClass(), "trigger") then return false end
    if string.find(ent:GetClass(), "func_") then return false end
    if string.find(ent:GetClass(), "env_") then return false end
    if string.find(ent:GetClass(), "point_") then return false end
    if ent.IsEffect and ent:IsEffect() then return false end
    if ent:IsConstraint() then return false end
    if ent:GetClass() == "fire" then return false end
    if ent:GetClass() == "smoke" then return false end
    if ent:GetClass() == "spark" then return false end
    if ent:GetClass() == "prop_physics" and ent:GetModel() == "" then return false end
    return true
end
local function IsHostileByDefault(ent)
    if not IsValidTarget(ent) then return false end
    if ent:IsPlayer() then
        if IsBotSafe(ent) then return false end
        local bot = GetCompanion()
        if AI_Utils.IsValid(bot) then
            local botID = bot:EntIndex()
            local owner = GetBotOwner(bot)
            if owner == ent then return false end
        end
        return true
    end
    if ent:IsNPC() then
        local class = SafeGetClass(ent)
        if FRIENDLY_NPC_CLASSES[class] then return false end
        return true
    end
    if ent:IsNextBot() then
        local class = SafeGetClass(ent)
        if FRIENDLY_NPC_CLASSES[class] then return false end
        return true
    end
    return false
end
FRIENDLY_NPC_CLASSES = FRIENDLY_NPC_CLASSES or {
    ["npc_citizen"] = true,
    ["npc_alyx"] = true,
    ["npc_barney"] = true,
    ["npc_dog"] = true,
    ["npc_magnusson"] = true,
    ["npc_kleiner"] = true,
    ["npc_eli"] = true,
    ["npc_monk"] = true
}
function AI_ForceCombatWeapon(bot)
    if not AI_Utils.IsValid(bot) then return end
    if not bot:Alive() then return end
    local combatWep = GetBotCombatWeapon(bot)
    if not combatWep or combatWep == "" then
        combatWep = "weapon_smg1"
    end
    if not bot:HasWeapon(combatWep) then
        SafeGiveWeapon(bot, combatWep)
        timer.Simple(0.1, function()
            if not AI_Utils.IsValid(bot) then return end
            local wep = bot:GetWeapon(combatWep)
            if AI_Utils.IsValid(wep) then
                local ammoType = wep:GetPrimaryAmmoType()
                if ammoType and ammoType ~= -1 then bot:GiveAmmo(120, ammoType, true) end
                if AI_CONFIG.INFINITE_AMMO then
                    local maxClip = wep:GetMaxClip1() or 30
                    if maxClip > 0 then wep:SetClip1(maxClip) end
                end
            end
        end)
    end
    bot:SelectWeapon(combatWep)
end
local GRENADE_DODGE_CLASSES = { ["npc_grenade_frag"] = true }
local GrenadeCache = { list = {}, lastUpdate = 0, updateInterval = 0.3, botPos = Vector(0, 0, 0) }
local function UpdateGrenadeCache(botPos)
    local now = CurTime()
    if now - GrenadeCache.lastUpdate < GrenadeCache.updateInterval then return end
    GrenadeCache.lastUpdate = now
    GrenadeCache.botPos = botPos
    GrenadeCache.list = {}
    for _, ent in ipairs(ents.GetAll()) do
        if AI_Utils.IsValid(ent) and GRENADE_DODGE_CLASSES[SafeGetClass(ent)] then
            local dist = botPos:Distance(SafeGetPos(ent))
            if dist < AI_CONFIG.Magic.Combat.GrenadeDodgeRadius then table.insert(GrenadeCache.list, ent) end
        end
    end
end
local function HandleGrenadeDodge(bot, cmd, navData)
    if not AI_Utils.IsValid(bot) or not cmd then return false end
    local botPos = SafeGetPos(bot)
    UpdateGrenadeCache(botPos)
    if #GrenadeCache.list == 0 then return false end
    local dodge = Vector(0, 0, 0)
    local closestDist = 999999
    for _, grenade in ipairs(GrenadeCache.list) do
        if AI_Utils.IsValid(grenade) then
            local dir = botPos - SafeGetPos(grenade)
            local dist = dir:Length()
            if dist < closestDist then closestDist = dist end
            if dist > 10 then dodge = dodge + dir:GetNormalized() end
        end
    end
    if dodge:LengthSqr() < 0.01 then return false end
    dodge:Normalize()
    ApplyWorldMovement(cmd, dodge, AI_CONFIG.Magic.Combat.DodgeSpeed)
    if closestDist < AI_CONFIG.Magic.Combat.GrenadeDangerDist then cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_JUMP)) end
    return true
end
local function GetThreatWeight(ent)
    if not IsValidTarget(ent) then return 0 end
    if not AI_Utils.IsValid(ent) then return 0 end
    local class = SafeGetClass(ent)
    local weight = AI_CONFIG.THREAT_WEIGHTS and AI_CONFIG.THREAT_WEIGHTS[class] or 1
    if ent:IsPlayer() then
        local wep = ent:GetActiveWeapon()
        if AI_Utils.IsValid(wep) then
            local wepClass = wep:GetClass()
            if wepClass == "weapon_rpg" or wepClass == "weapon_rocketlauncher" then weight = 5 end
        end
        return weight * 2
    end
    return weight
end
local function SelectHighestThreat(bot, enemies)
    local best, bestWeight = nil, -1
    for _, ent in ipairs(enemies) do
        if AI_Utils.IsValid(ent) and SafeAlive(ent) and IsValidTarget(ent) then
            local w = GetThreatWeight(ent)
            if w > bestWeight then bestWeight = w best = ent end
        end
    end
    return best
end
local function CanSeeTarget(bot, target)
    if not AI_Utils.IsValid(bot) or not AI_Utils.IsValid(target) then return false end
    local tr = util.TraceLine({
        start = bot:EyePos(),
        endpos = target:WorldSpaceCenter(),
        filter = bot,
        mask = MASK_SHOT
    })
    if not tr.Hit then return true end
    if AI_Utils.IsValid(tr.Entity) and tr.Entity == target then return true end
    return false
end
function AI_ForceMeleeWeapon(bot)
    if not AI_Utils.IsValid(bot) then return end
    if not bot:Alive() then return end
    local meleeWep = GetBotMeleeWeapon(bot)
    if not meleeWep or meleeWep == "" then
        meleeWep = "weapon_crowbar"
    end
    if not bot:HasWeapon(meleeWep) then
        SafeGiveWeapon(bot, meleeWep)
    end
    bot:SelectWeapon(meleeWep)
end
local function SpawnHealKit(pos, amount)
    local kit = ents.Create("item_healthkit")
    if not AI_Utils.IsValid(kit) then return end
    local spawnPos = pos + Vector(0, 0, 8)
    kit:SetPos(spawnPos)
    kit:Spawn()
    local phys = kit:GetPhysicsObject()
    if AI_Utils.IsValid(phys) then
        phys:Wake()
        phys:SetVelocity(Vector(math.Rand(-10, 10), math.Rand(-10, 10), 30))
    end
    timer.Simple(30, function()
        if AI_Utils.IsValid(kit) then kit:Remove() end
    end)
end
function HandleMedicMode(bot, cmd)
    if not IsMedicMode(bot) then return false end
    if not IsValid(bot) or not bot:Alive() then return false end
    if AI_Utils.IsPassenger(bot) then return false end
    local botID = bot:EntIndex()
    local data = GetBotData(bot)
    local isInCombat = data and data.combat and IsValid(data.combat.target)
    if isInCombat then return false end
    local owner = GetBotOwner(bot)
    local healTarget = nil
    if IsValid(owner) and owner:Alive() then
        local ownerHpPct = owner:Health() / math.max(owner:GetMaxHealth(), 1)
        if ownerHpPct < 0.7 then
            healTarget = owner
        end
    end
    if not healTarget then
        local botHpPct = bot:Health() / math.max(bot:GetMaxHealth(), 1)
        if botHpPct < 0.5 then
            healTarget = bot
        end
    end
    if not healTarget then
        local idleWep = GetBotIdleWeapon(bot)
        if bot:HasWeapon(idleWep) then
            bot:SelectWeapon(idleWep)
        end
        return false
    end
    if not bot:HasWeapon("weapon_medkit") then
        SafeGiveWeapon(bot, "weapon_medkit")
        timer.Simple(0.1, function()
            if IsValid(bot) and bot:HasWeapon("weapon_medkit") then
                bot:SelectWeapon("weapon_medkit")
            end
        end)
        return true
    end
    local aw = bot:GetActiveWeapon()
    if not IsValid(aw) or aw:GetClass() ~= "weapon_medkit" then
        bot:SelectWeapon("weapon_medkit")
        return true
    end
    local aimPos = healTarget:GetPos() + Vector(0, 0, 45)
    local aimDir = aimPos - bot:EyePos()
    if aimDir:LengthSqr() > 0.001 then
        aimDir:Normalize()
        local aimAng = aimDir:Angle()
        bot:SetEyeAngles(aimAng)
        if cmd then
            cmd:SetViewAngles(aimAng)
        end
    end
    if healTarget == bot then
        bot._aiMedicSelfHeal = true
        if cmd then
            cmd:ClearMovement()
        end
        local timerKey = "AI_MedkitSpawn_" .. botID
        if not timer.Exists(timerKey) then
            if cmd then
                cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_ATTACK))
            end
            local kit = ents.Create("item_healthkit")
            if IsValid(kit) then
                kit:SetPos(bot:GetPos() + Vector(0, 0, 8))
                kit:Spawn()
                local effect = EffectData()
                effect:SetOrigin(bot:GetPos() + Vector(0, 0, 40))
                util.Effect("cball_explode", effect)
                timer.Simple(8, function()
                    if IsValid(kit) then kit:Remove() end
                end)
            end
            timer.Create(timerKey, 2, 1, function() end)
        end
        return true
    else
        bot._aiMedicSelfHeal = nil
    end
    local dist = bot:GetPos():Distance(healTarget:GetPos())
    if dist <= 100 then
        local timerKey = "AI_MedkitSpawn_" .. botID
        if not timer.Exists(timerKey) then
            if cmd then
                cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_ATTACK))
            end
            local kit = ents.Create("item_healthkit")
            if IsValid(kit) then
                kit:SetPos(healTarget:GetPos() + Vector(0, 0, 8))
                kit:Spawn()
                local effect = EffectData()
                effect:SetOrigin(healTarget:GetPos() + Vector(0, 0, 40))
                util.Effect("cball_explode", effect)
                timer.Simple(8, function()
                    if IsValid(kit) then kit:Remove() end
                end)
            end
            timer.Create(timerKey, 2, 1, function() end)
        end
        return true
    else
        if cmd then
            local runDir = healTarget:GetPos() - bot:GetPos()
            runDir.z = 0
            if runDir:LengthSqr() > 0.001 then
                runDir:Normalize()
                ApplyWorldMovement(cmd, runDir, AI.Config.Speeds.Walk or 250)
            end
        end
        return true
    end
end
function HandleCombat(bot, cmd)
    if not AI_Utils.IsValid(bot) then return false end
    if not bot:Alive() then return false end
    if AI_Utils.IsPassenger(bot) then return false end
    local botID = bot:EntIndex()
    local data = GetBotData(bot)
    if not data then return false end
    local owner = GetBotOwner(bot)
    if data.combat and data.combat.triggered_by == "command_llm" 
       and IsValid(data.combat.target) and data.combat.target == owner then
    end
    if data.config.pacifist_mode then
        data.combat.target = nil
        SetBotState(bot, AC.Companion.States.IDLE)
        ComeBackToPlayer(bot)
        local idleWep = GetBotIdleWeapon(bot)
        if bot:HasWeapon(idleWep) then bot:SelectWeapon(idleWep) end
        return false
    end
    local medkitTimer = "AI_MedkitSpawn_" .. botID
    if timer.Exists(medkitTimer) then timer.Remove(medkitTimer) end
    local target = data.combat.target
    if not IsValidTarget(target) then
        data.combat.target = nil
        data.combat.last_combat_end = CurTime()
        SetBotState(bot, AC.Companion.States.IDLE)
        ComeBackToPlayer(bot)
        return false
    end
    if not SafeAlive(target) then
        data.combat.target = nil
        data.combat.last_combat_end = CurTime()
        SetBotState(bot, AC.Companion.States.IDLE)
        ComeBackToPlayer(bot)
        return false
    end
    local botPos = SafeGetPos(bot)
    local targetPos = target:WorldSpaceCenter()
    local dist = targetPos and botPos and botPos:Distance(targetPos) or 999999
    if not HasAnyAmmo(bot) then
        local meleeWep = GetBotMeleeWeapon(bot)
        if not bot:HasWeapon(meleeWep) then
            SafeGiveWeapon(bot, meleeWep)
            if meleeWep ~= "weapon_crowbar" and meleeWep ~= "weapon_stunstick" then
                local mw = bot:GetWeapon(meleeWep)
                if AI_Utils.IsValid(mw) then
                    GivePrimaryAmmo(bot, mw, 30)
                end
            end
        end
        bot:SelectWeapon(meleeWep)
        local aw = bot:GetActiveWeapon()
        if not AI_Utils.IsValid(aw) or aw:GetClass() ~= meleeWep then
            data.combat.weapon_switch_wait = (data.combat.weapon_switch_wait or 0) + 1
            if data.combat.weapon_switch_wait < AI_CONFIG.Magic.Combat.WeaponSwitchDelay then
                return true
            end
            data.combat.weapon_switch_wait = 0
        else
            data.combat.weapon_switch_wait = 0
        end
        local aimPos = GetTargetAimPos(target)
        local aimDir = aimPos - bot:EyePos()
        if aimDir:LengthSqr() > 0.001 then
            aimDir:Normalize()
            local aimAng = aimDir:Angle()
            bot:SetEyeAngles(aimAng)
            cmd:SetViewAngles(aimAng)
            bot._aiAimDir = aimDir
        end
        local botPos = SafeGetPos(bot)
        local tPos = SafeGetPos(target)
        local dirToTarget = tPos - botPos
        local flatDist = Vector(dirToTarget.x, dirToTarget.y, 0):Length()
        dirToTarget.z = 0
        local idealMeleeDist = 45
        if flatDist > AI_CONFIG.Magic.Combat.MeleeDist then
            if dirToTarget:LengthSqr() > 0.001 then
                dirToTarget:Normalize()
                ApplyWorldMovement(cmd, dirToTarget, AI_CONFIG.Magic.Combat.MeleeSpeed * 1.5)
            end
            return true
        end
        if flatDist <= AI_CONFIG.Magic.Combat.MeleeDist then
            if CanSeeTarget(bot, target) then
                cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_ATTACK))
                data.combat.last_attack_time = CurTime()
            end
            if flatDist > idealMeleeDist + 10 then
                if dirToTarget:LengthSqr() > 0.001 then
                    dirToTarget:Normalize()
                    ApplyWorldMovement(cmd, dirToTarget, AI_CONFIG.Magic.Combat.MeleeSpeed)
                end
            elseif flatDist < idealMeleeDist - 15 then
                if dirToTarget:LengthSqr() > 0.001 then
                    dirToTarget:Normalize()
                    ApplyWorldMovement(cmd, -dirToTarget, AI_CONFIG.Magic.Combat.MeleeSpeed * 0.5)
                end
            else
                if not data.combat.next_strafe_change or CurTime() > data.combat.next_strafe_change then
                    data.combat.strafe_dir = math.random() > 0.5 and 1 or -1
                    data.combat.next_strafe_change = CurTime() + 0.5
                end
                local rgt = aimAng:Right()
                rgt.z = 0
                if rgt:LengthSqr() < 0.001 then rgt = Vector(0, 1, 0) end
                rgt:Normalize()
                local strafeDir = rgt * data.combat.strafe_dir
                ApplyWorldMovement(cmd, strafeDir, AI_CONFIG.Magic.Combat.MeleeSpeed * 0.4)
            end
            return true
        end
        return true
    end
    local forgetRadius = AI_CONFIG.Magic.Combat.CombatForgetRadius or 3000
    if dist and dist > forgetRadius then
        data.combat.target = nil
        data.combat.last_combat_end = CurTime()
        SetBotState(bot, AC.Companion.States.IDLE)
        ComeBackToPlayer(bot)
        if AI_Utils.IsValid(bot) then bot:ChatPrint("[AI] Цель слишком далеко, возвращаюсь.") end
        return false
    end
    local combatIdleTimeout = AI_CONFIG.Magic.Combat.CombatIdleTimeout or 10.0
    local isMeleeMode = dist < AI_CONFIG.Magic.Combat.MeleeDist
    local effectiveTimeout = isMeleeMode and (combatIdleTimeout * 3) or combatIdleTimeout
    if data.combat.last_attack_time and (CurTime() - data.combat.last_attack_time) > effectiveTimeout then
        if dist > 500 then
            data.combat.target = nil
            data.combat.last_combat_end = CurTime()
            SetBotState(bot, AC.Companion.States.IDLE)
            ComeBackToPlayer(bot)
            if AI_Utils.IsValid(bot) then bot:ChatPrint("[AI] Цель потеряна, возвращаюсь.") end
            return false
        end
    end
    if HandleGrenadeDodge(bot, cmd, {}) then return true end
    local meleeWep = GetBotMeleeWeapon(bot)
    if dist < AI_CONFIG.Magic.Combat.MeleeDist then
        if not bot:HasWeapon(meleeWep) then
            local lastMeleeGive = data.combat.last_melee_give or 0
            if CurTime() - lastMeleeGive > AI.Config.Combat.MeleeGiveCooldown or 1.0 then
                SafeGiveWeapon(bot, meleeWep)
                data.combat.last_melee_give = CurTime()
                if meleeWep ~= "weapon_crowbar" and meleeWep ~= "weapon_stunstick" then
                    local mw = bot:GetWeapon(meleeWep)
                    if AI_Utils.IsValid(mw) then
                        GivePrimaryAmmo(bot, mw, 30)
                    end
                end
            end
        end
        if bot:HasWeapon(meleeWep) then
            local aw = bot:GetActiveWeapon()
            if not AI_Utils.IsValid(aw) or aw:GetClass() ~= meleeWep then
                bot:SelectWeapon(meleeWep)
                data.combat.weapon_switch_wait = (data.combat.weapon_switch_wait or 0) + 1
                if data.combat.weapon_switch_wait < AI_CONFIG.Magic.Combat.WeaponSwitchDelay then
                    return true
                end
                data.combat.weapon_switch_wait = 0
            else
                data.combat.weapon_switch_wait = 0
            end
            aw = bot:GetActiveWeapon()
            if AI_Utils.IsValid(aw) and aw:GetClass() == meleeWep then
                local aimPos = GetTargetAimPos(target)
                local aimDir = aimPos - bot:EyePos()
                if aimDir:LengthSqr() > 0.001 then
                    aimDir:Normalize()
                    local aimAng = aimDir:Angle()
                    bot:SetEyeAngles(aimAng)
                    cmd:SetViewAngles(aimAng)
                    bot._aiAimDir = aimDir
                    data.combat.last_attack_time = CurTime()
                    if CanSeeTarget(bot, target) then
                        cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_ATTACK))
                    end
                    local bPos = SafeGetPos(bot)
                    local tPos = SafeGetPos(target)
                    local dirToTarget = tPos - bPos
                    dirToTarget.z = 0
                    local idealMeleeDist = 45
                    local moveDir = Vector(0, 0, 0)
                    if dirToTarget:LengthSqr() > 0.001 then
                        dirToTarget:Normalize()
                        if dist > idealMeleeDist + 10 then
                            moveDir = dirToTarget
                        elseif dist < idealMeleeDist - 15 then
                            moveDir = -dirToTarget
                        else
                            if not data.combat.next_strafe_change or CurTime() > data.combat.next_strafe_change then
                                data.combat.strafe_dir = math.random() > 0.5 and 1 or -1
                                data.combat.next_strafe_change = CurTime() + 0.5
                            end
                            local rgt = aimAng:Right()
                            rgt.z = 0
                            if rgt:LengthSqr() < 0.001 then rgt = Vector(0, 1, 0) end
                            rgt:Normalize()
                            moveDir = rgt * data.combat.strafe_dir * 0.3
                        end
                        local checkTr = util.TraceHull({
                            start = bPos + Vector(0, 0, 15),
                            endpos = bPos + Vector(0, 0, 15) + moveDir * 40,
                            mins = Vector(-12, -12, 0),
                            maxs = Vector(12, 12, 20),
                            filter = bot,
                            mask = MASK_PLAYERSOLID
                        })
                        if checkTr.Hit and not checkTr.StartSolid then
                            moveDir = Vector(0, 0, 0)
                        end
                        if moveDir:LengthSqr() > 0.001 then
                            ApplyWorldMovement(cmd, moveDir, AI_CONFIG.Magic.Combat.MeleeSpeed)
                        end
                    end
                    return true
                end
            end
        end
    end
    local desiredWep, weaponMode = SelectBestWeapon(bot, target, dist)
    if not bot:HasWeapon(desiredWep) then
        SafeGiveWeapon(bot, desiredWep)
        local waitTicks = (desiredWep == "weapon_rpg") and 3 or 1
        data.combat.weapon_wait_ticks = (data.combat.weapon_wait_ticks or 0) + 1
        if data.combat.weapon_wait_ticks < waitTicks then return true end
        data.combat.weapon_wait_ticks = 0
    else
        data.combat.weapon_wait_ticks = 0
    end
    local aw = bot:GetActiveWeapon()
    local awClass = AI_Utils.IsValid(aw) and aw:GetClass() or "NONE"
    if awClass ~= desiredWep then
        bot:SelectWeapon(desiredWep)
        data.combat.weapon_switch_wait = (data.combat.weapon_switch_wait or 0) + 1
        if data.combat.weapon_switch_wait < AI_CONFIG.Magic.Combat.WeaponSwitchDelay then return true end
        data.combat.weapon_switch_wait = 0
    else
        data.combat.weapon_switch_wait = 0
    end
    if AI_CONFIG.INFINITE_AMMO then
        local wep = bot:GetActiveWeapon()
        if AI_Utils.IsValid(wep) then
            if wep:Clip1() <= 0 then
                local ammoType = wep:GetPrimaryAmmoType()
                if ammoType and ammoType ~= -1 then
                    bot:GiveAmmo(AI.Config.Combat.AmmoGiveAmount or 100, ammoType, true)
                    wep:SetClip1(wep:GetMaxClip1() > 0 and wep:GetMaxClip1() or 30)
                end
            end
        end
    end
    local MELEE_WEAPONS = { ["weapon_crowbar"] = true, ["weapon_stunstick"] = true }
    local isMelee = MELEE_WEAPONS[desiredWep] or false
    local isRPG = weaponMode == "rpg"
    local isFrag = weaponMode == "frag"
    local aimPos = GetTargetAimPos(target)
    local targetVel = target:GetVelocity() or Vector(0,0,0)
    local bulletSpeed = 5000
    local timeToTarget = dist / bulletSpeed
    aimPos = aimPos + targetVel * timeToTarget
    local aimDir = aimPos - bot:EyePos()
    if aimDir:LengthSqr() < 0.001 then return true end
    aimDir:Normalize()
    local aimAng = aimDir:Angle()
    bot:SetEyeAngles(aimAng)
    cmd:SetViewAngles(aimAng)
    bot._aiAimDir = aimDir
    local canSee = CanSeeTarget(bot, target)
    local canShoot = canSee
    if isRPG then
        local active = bot:GetActiveWeapon()
        if not AI_Utils.IsValid(active) or active:GetClass() ~= "weapon_rpg" then
            bot:SelectWeapon("weapon_rpg")
            return true
        end
        local canFireRPG = CurTime() - (data.combat.rpg_last_fire or 0) >= AI_CONFIG.Magic.Combat.RPGCooldown
        if canFireRPG and canShoot then
            cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_ATTACK))
            data.combat.rpg_last_fire = CurTime()
            data.combat.last_attack_time = CurTime()
        end
    elseif isFrag then
        if CurTime() - (data.combat.frag_last_throw or 0) >= AI_CONFIG.Magic.Combat.FragCooldown then
            local throwAimPos = targetPos + Vector(0, 0, 30)
            local throwDir = throwAimPos - bot:EyePos()
            if throwDir:LengthSqr() > 0.001 then
                throwDir:Normalize()
                local throwAng = throwDir:Angle()
                throwAng.p = throwAng.p - 15
                bot:SetEyeAngles(throwAng)
                cmd:SetViewAngles(throwAng)
            end
            if dist < AI_CONFIG.Magic.Combat.FragMaxDist and dist > AI_CONFIG.Magic.Combat.FragMinDist then
                cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_ATTACK))
                data.combat.frag_last_throw = CurTime()
                data.combat.last_attack_time = CurTime()
            end
        end
    elseif canShoot then
        local atkBtns = IN_ATTACK
        if CurTime() - (data.combat.alt_fire_timer or 0) > AI_CONFIG.Magic.Combat.AltFireCooldown then
            atkBtns = bit.bor(atkBtns, IN_ATTACK2)
            data.combat.alt_fire_timer = CurTime()
        end
        cmd:SetButtons(bit.bor(cmd:GetButtons(), atkBtns))
        data.combat.last_attack_time = CurTime()
    end
    local idealDist = AI_CONFIG.Magic.Combat.IdealDist
    if isMelee then idealDist = AI_CONFIG.Magic.Combat.MeleeDist
    elseif isRPG then idealDist = AI_CONFIG.Magic.Combat.RPGDist
    elseif isFrag then idealDist = AI_CONFIG.Magic.Combat.FragMinDist + 50
    elseif AI_CONFIG.IDEAL_COMBAT_DIST then idealDist = AI_CONFIG.IDEAL_COMBAT_DIST[desiredWep] or AI_CONFIG.Magic.Combat.IdealDist end
    local flatAim = Vector(aimDir.x, aimDir.y, 0)
    if flatAim:LengthSqr() < 0.001 then flatAim = Vector(1, 0, 0) end
    flatAim:Normalize()
    local useNav = false
    local movePos = nil
    if isMelee then
        if dist > idealDist * 1.5 then useNav = true movePos = targetPos
        elseif dist > idealDist then
            local forwardDir = flatAim
            movePos = botPos + forwardDir * 150
        elseif dist < idealDist * 0.5 then
            local backDir = -flatAim
            movePos = botPos + backDir * AI_CONFIG.Magic.Combat.StrafeDist
        else
            if not data.combat.next_strafe_change or CurTime() > data.combat.next_strafe_change then
                data.combat.strafe_dir = math.random() > 0.5 and 1 or -1
                data.combat.next_strafe_change = CurTime() + math.Rand(AI_CONFIG.Magic.Combat.StrafeMinInterval, 0.9)
            end
            local rgt = aimAng:Right()
            rgt.z = 0
            if rgt:LengthSqr() < 0.001 then rgt = Vector(0, 1, 0) end
            rgt:Normalize()
            movePos = botPos + rgt * data.combat.strafe_dir * AI_CONFIG.Magic.Combat.StrafeDist
        end
    else
        if (not canSee) or dist > idealDist * 1.35 then useNav = true movePos = targetPos
        elseif dist < idealDist * 0.65 then
            local backDir = -flatAim
            movePos = botPos + backDir * 110
        else
            if not data.combat.next_strafe_change or CurTime() > data.combat.next_strafe_change then
                data.combat.strafe_dir = math.random() > 0.5 and 1 or -1
                data.combat.next_strafe_change = CurTime() + math.Rand(AI_CONFIG.Magic.Combat.StrafeMinInterval, AI_CONFIG.Magic.Combat.StrafeMaxInterval)
            end
            local rgt = aimAng:Right()
            rgt.z = 0
            if rgt:LengthSqr() < 0.001 then rgt = Vector(0, 1, 0) end
            rgt:Normalize()
            movePos = botPos + rgt * data.combat.strafe_dir * AI_CONFIG.Magic.Combat.CombatStrafeDist
        end
    end
    if useNav and AI_Companion_MoveToTarget then
        AI_Companion_MoveToTarget(bot, cmd, movePos or targetPos, target)
    elseif movePos then
        local runDir = movePos - botPos
        runDir.z = 0
        if runDir:LengthSqr() > 0.001 then
            runDir:Normalize()
            local moveSpeed = isMelee and AI_CONFIG.Magic.Combat.MeleeSpeed or AI_CONFIG.Magic.Combat.CombatSpeed
            ApplyWorldMovement(cmd, runDir, moveSpeed)
        end
    end
    local currentBtns = cmd:GetButtons()
    cmd:SetButtons(bit.band(currentBtns, bit.bnot(IN_DUCK)))
    bot:RemoveFlags(FL_DUCKING)
    bot:RemoveFlags(FL_ANIMDUCKING)
    bot._aiStealthCrouch = false
    return true
end
hook.Add("StartCommand", "AICompanion_MedicInFollow_v3", function(bot, cmd)
    if not AI_Utils.IsValid(bot) or not bot:IsBot() then return end
    if not bot:GetNWBool("IsAICompanion", false) then return end
    local botID = bot:EntIndex()
    local data = GetBotData(bot)
    if data and data.combat and IsValid(data.combat.target) then return end
    local botState = GetBotState(bot)
    if botState == AC.Companion.States.VEHICLE or botState == AC.Companion.States.SITTING then return end
    HandleMedicMode(bot, cmd)
end)
local enemyCache = {}
local enemyCacheTime = 0
local function UpdateEnemyCache()
    if CurTime() - enemyCacheTime < AI.Config.Combat.EnemyCacheInterval or 2 then return end
    enemyCacheTime = CurTime()
    enemyCache = {}
    for _, ent in ipairs(ents.FindByClass("npc_*")) do
        if AI_Utils.IsValid(ent) and ent:Alive() and IsValidTarget(ent) then
            local class = SafeGetClass(ent)
            if not FRIENDLY_NPC_CLASSES[class] then table.insert(enemyCache, ent) end
        end
    end
    for _, ply in ipairs(player.GetAll()) do
        if AI_Utils.IsValid(ply) and ply:Alive() and not ply:IsBot() and IsValidTarget(ply) then
            local bot = GetCompanion()
            if AI_Utils.IsValid(bot) then
                local botID = bot:EntIndex()
                local owner = GetBotOwner(bot)
                if owner ~= ply then
                    table.insert(enemyCache, ply)
                end
            else
                table.insert(enemyCache, ply)
            end
        end
    end
end
local scanTimer = "AICompanion_AggressiveScan"
if timer.Exists(scanTimer) then timer.Remove(scanTimer) end
timer.Create(scanTimer, AI_CONFIG.Magic.Combat.ThreatScanInterval, 0, function()
    UpdateEnemyCache()
    local bots = GetAllCompanions()
    for _, bot in ipairs(bots) do
        if not IsValid(bot) or not bot:Alive() then continue end
        if AI_Utils.IsPassenger(bot) then continue end
        if bot:InVehicle() then continue end
        local data = GetBotData(bot)
        if not data then continue end
        if not data.config.aggressive_mode then continue end
        local botID = bot:EntIndex()
        if data.combat.target and IsValidTarget(data.combat.target) and SafeAlive(data.combat.target) then
            continue
        end
        if data.combat.target then
            data.combat.target = nil
            SetBotState(bot, AC.Companion.States.IDLE)
            ComeBackToPlayer(bot)
            continue
        end
        local botState = GetBotState(bot)
        if botState == AC.Companion.States.POINTING then continue end
        local botPos = SafeGetPos(bot)
        local scanRadius = AI_CONFIG.Magic.Combat.ThreatScanRadius
        local nearestEnemy, nearestDist = nil, scanRadius
        for _, ent in ipairs(enemyCache) do
            if not AI_Utils.IsValid(ent) then continue end
            if ent == bot then continue end
            if not IsValidTarget(ent) then continue end
            local dist = botPos:Distance(SafeGetPos(ent))
            if dist < nearestDist then
                nearestDist = dist
                nearestEnemy = ent
            end
        end
        if AI_Utils.IsValid(nearestEnemy) then
            data.combat.target = nearestEnemy
            data.combat.target_type = "npc"
            data.combat.triggered_by = "aggressive"
            data.combat.last_attack_time = CurTime()
            SetBotState(bot, AC.Companion.States.COMBAT)
            AI_ForceCombatWeapon(bot)
            if AI_Utils.IsValid(bot) then
                bot:ChatPrint("[AI] Агрессивный режим: атакую " .. SafeGetClass(nearestEnemy))
            end
        end
    end
end)
hook.Add("EntityTakeDamage", "AICompanion_AssistAndProtect_v5", function(victim, dmg)
    if _G.AI_Companion_Disabled then return end
    if not IsValid(victim) then return end
    if not IsValidTarget(victim) then return end
    local attacker = dmg:GetAttacker()
    if not IsValid(attacker) then return end
    if not IsValidTarget(attacker) then return end
    if attacker == victim or attacker:IsWorld() then return end
    local okAlive, attackerAlive = pcall(function() return attacker:Alive() end)
    if not okAlive or not attackerAlive then return end
    local bot = nil
    local botID = nil
    local owner = nil
    if victim:IsPlayer() and victim:IsBot() and victim:GetNWBool("IsAICompanion", false) then
        bot = victim
        botID = bot:EntIndex()
        owner = GetBotOwner(bot)
    end
    if not IsValid(bot) then
        for _, b in ipairs(GetAllCompanions()) do
            if IsValid(b) then
                local bID = b:EntIndex()
                local bOwner = GetBotOwner(b)
                if bOwner == attacker then
                    bot = b
                    botID = bID
                    owner = bOwner
                    break
                end
                if bOwner == victim then
                    bot = b
                    botID = bID
                    owner = bOwner
                    break
                end
            end
        end
    end
    if not IsValid(bot) then return end
    if AI_Utils.IsPassenger(bot) then return end
    botID = botID or bot:EntIndex()
    owner = owner or GetBotOwner(bot)
    if attacker == bot then return end
    local data = GetBotData(bot)
    if not data then return end
    if data.config.pacifist_mode then return end
    data.combat.last_damage_time = CurTime()
    if IsValid(owner) and attacker == owner and victim == bot then
        if data.combat and data.combat.triggered_by == "command_llm" and data.combat.target == owner then
            return
        end
        data.combat.target = attacker
        data.combat.target_type = "player"
        data.combat.triggered_by = "owner_attack"
        data.combat.last_attack_time = CurTime()
        SetBotState(bot, AC.Companion.States.COMBAT)
        AI_ForceCombatWeapon(bot)
        if IsValid(bot) then
            bot:ChatPrint("[AI] Хозяин, прекратите! Защищаюсь!")
        end
        return
    end
    if victim == bot then
        if not IsValidTarget(attacker) then return end
        if data.combat and data.combat.triggered_by == "command_llm" and IsValid(data.combat.target) then
            return
        end
        local dist = bot:GetPos():Distance(attacker:GetPos())
        local meleeWep = GetBotMeleeWeapon(bot)
        if dist < AI_CONFIG.Magic.Combat.MeleeDist and bot:HasWeapon(meleeWep) then
            return
        end
        data.combat.target = attacker
        data.combat.target_type = IsPlayerSafe(attacker) and "player" or "npc"
        data.combat.triggered_by = "damage"
        data.combat.last_attack_time = CurTime()
        SetBotState(bot, AC.Companion.States.COMBAT)
        AI_ForceCombatWeapon(bot)
        if IsValid(bot) then
            local name = IsPlayerSafe(attacker) and attacker:Nick() or SafeGetClass(attacker)
            bot:ChatPrint("[AI] Меня атакуют! Защищаюсь от " .. name)
        end
        return
    end
    if IsValid(owner) and attacker == owner and victim ~= bot then
        if not data.config.defender_mode then return end
        if not IsValidTarget(victim) then return end
        local isTargetValid = victim:IsNPC() or victim:IsNextBot() or IsPlayerSafe(victim)
        if isTargetValid then
            if data.combat.target == victim then return end
            data.combat.target = victim
            data.combat.target_type = IsPlayerSafe(victim) and "player" or "npc"
            data.combat.triggered_by = "assist"
            data.combat.last_attack_time = CurTime()
            SetBotState(bot, AC.Companion.States.COMBAT)
            AI_ForceCombatWeapon(bot)
            if IsValid(owner) then
                local name = IsPlayerSafe(victim) and victim:Nick() or victim:GetClass()
                owner:ChatPrint("[AI] Помогаю уничтожить " .. name)
            end
        end
        return
    end
    if victim == owner then
        if not data.config.defender_mode then return end
        if not IsValidTarget(attacker) then return end
        if data.combat.target == attacker then return end
        data.combat.target = attacker
        data.combat.target_type = IsPlayerSafe(attacker) and "player" or "npc"
        data.combat.triggered_by = "protect"
        data.combat.last_attack_time = CurTime()
        SetBotState(bot, AC.Companion.States.PROTECT)
        AI_ForceCombatWeapon(bot)
        if IsValid(bot) and IsValid(owner) then
            local name = IsPlayerSafe(attacker) and attacker:Nick() or SafeGetClass(attacker)
            owner:ChatPrint("[AI] Защищаю вас от " .. name)
        end
        return
    end
    if IsValid(victim) and victim.IsGlideVehicle then
        local vehicle = victim
        local driver = vehicle:GetDriver()
        if IsValid(driver) and (driver == bot or driver == owner) then
            if not data.config.defender_mode then return end
            if not IsValidTarget(attacker) then return end
            if data.combat.target == attacker then return end
            data.combat.target = attacker
            data.combat.target_type = IsPlayerSafe(attacker) and "player" or "npc"
            data.combat.triggered_by = "protect_vehicle"
            data.combat.last_attack_time = CurTime()
            SetBotState(bot, AC.Companion.States.PROTECT_VEHICLE)
            AI_ForceCombatWeapon(bot)
            if IsValid(bot) and IsValid(owner) then
                local name = IsPlayerSafe(attacker) and attacker:Nick() or SafeGetClass(attacker)
                owner:ChatPrint("[AI] Атакуют наш транспорт! Защищаю от " .. name)
            end
        end
        return
    end
end)
hook.Add("EntityFireBullets", "AICompanion_AimbotCorrection_v3", function(ent, data)
    if not IsValid(ent) or not IsBotSafe(ent) or not ent:GetNWBool("IsAICompanion", false) then return end
    local botData = GetBotData(ent)
    if not botData or not botData.combat.target then return end
    local target = botData.combat.target
    if not IsValidTarget(target) then return end
    local aimPos = GetTargetAimPos(target)
    local targetVel = target:GetVelocity() or Vector(0,0,0)
    local shootPos = ent:GetShootPos()
    local dist = shootPos:Distance(aimPos)
    local bulletSpeed = 5000
    local timeToTarget = math.max(dist / bulletSpeed, 0.01)
    aimPos = aimPos + targetVel * timeToTarget
    local rawDir = aimPos - shootPos
    if rawDir:LengthSqr() > 1e-4 then
        local aimDir = rawDir:GetNormalized()
        local aimAng = aimDir:Angle()
        ent:SetEyeAngles(aimAng)
        ent._aiAimDir = aimDir
        data.Dir = aimDir
        data.Spread = Vector(0, 0, 0)
        local checkTrace = util.TraceLine({ start = shootPos, endpos = aimPos, filter = ent, mask = MASK_SHOT })
        if checkTrace.Hit and checkTrace.Entity and checkTrace.Entity ~= target then
            if checkTrace.Entity:IsWorld() then
                local newAimPos = aimPos + Vector(0, 0, 15)
                local newDir = (newAimPos - shootPos):GetNormalized()
                data.Dir = newDir
                ent:SetEyeAngles(newDir:Angle())
            end
        end
    end
    return true
end)
local function CleanupCombatState(bot)
    if not AI_Utils.IsValid(bot) then return end
    local data = GetBotData(bot)
    if not data then return end
    if data.combat.target then
        data.combat.target = nil
        data.combat.target_type = nil
        data.combat.triggered_by = nil
        data.combat.last_combat_end = CurTime()
        SetBotState(bot, AC.Companion.States.IDLE)
        ComeBackToPlayer(bot)
        local idleWep = GetBotIdleWeapon(bot)
        if bot:HasWeapon(idleWep) then
            bot:SelectWeapon(idleWep)
        end
    end
end
hook.Add("PlayerDeath", "AICompanion_ForgetGrudge_v3", function(victim)
    if not AI_Utils.IsValid(victim) then return end
    local bots = GetAllCompanions()
    for _, bot in ipairs(bots) do
        local data = GetBotData(bot)
        if data and data.combat.target == victim then
            data.combat.last_combat_end = CurTime()
            CleanupCombatState(bot)
        end
    end
end)
hook.Add("OnNPCKilled", "AICompanion_ForgetNPCGrudge_v3", function(npc, attacker, inflictor)
    if not AI_Utils.IsValid(npc) then return end
    local bots = GetAllCompanions()
    for _, bot in ipairs(bots) do
        local data = GetBotData(bot)
        if data and data.combat.target == npc then
            data.combat.last_combat_end = CurTime()
            CleanupCombatState(bot)
        end
    end
end)
hook.Add("EntityRemoved", "AICompanion_TargetRemoved_v3", function(ent)
    if not AI_Utils.IsValid(ent) then return end
    local bot = GetCompanion()
    if not AI_Utils.IsValid(bot) then return end
    local data = GetBotData(bot)
    if data and data.combat.target == ent then
        data.combat.last_combat_end = CurTime()
        CleanupCombatState(bot)
    end
end)
hook.Add("PlayerDisconnected", "AICompanion_TargetDisconnected_v3", function(ply)
    if not AI_Utils.IsValid(ply) then return end
    local bot = GetCompanion()
    if not AI_Utils.IsValid(bot) then return end
    local data = GetBotData(bot)
    if data and data.combat.target == ply then
        data.combat.last_combat_end = CurTime()
        CleanupCombatState(bot)
    end
end)
hook.Add("PlayerSpawn", "AICompanion_ReFollowOnSpawn_v3", function(ply)
    if not AI_Utils.IsValid(ply) or IsBotSafe(ply) then return end
    timer.Simple(0.1, function()
        if not AI_Utils.IsValid(ply) or not ply:Alive() then return end
        local bots = GetAllCompanions()
        for _, bot in ipairs(bots) do
            if not AI_Utils.IsValid(bot) or not bot:Alive() then continue end
            local botID = bot:EntIndex()
            local data = GetBotData(bot)
            if data and data.owner == ply then
                if not data.combat.target or not IsValid(data.combat.target) then
                    SetBotState(bot, AC.Companion.States.FOLLOW)
                    if AI_Utils.IsValid(bot) then
                        bot:ChatPrint("[AI] С возвращением! Снова следую за вами.")
                    end
                end
            end
        end
    end)
end)
_G.HandleCombat = HandleCombat
_G.HandleMedicMode = HandleMedicMode
_G.AI_ForceCombatWeapon = AI_ForceCombatWeapon
_G.GetTargetAimPos = GetTargetAimPos
AI_DebugPrint("[AI Combat] v5.1 загружен (исправлен BotOwners -> GetBotOwner, AI_Companion init)")