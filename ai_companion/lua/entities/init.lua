if game.IsDedicated() then
    return
end

if game.MaxPlayers() > 1 then
    return
end

ENT.Type = "nextbot"
ENT.Base = "drgbase_nextbot_human"

local function FindCompanion()
    for _, ent in ipairs(ents.FindByClass("solo_companion_npc")) do
        if IsValid(ent) then return ent end
    end
    return nil
end

if SERVER then
    util.AddNetworkString("gmod.one/ai-companion/solo-request-settings")
    util.AddNetworkString("gmod.one/ai-companion/solo-send-settings")

    net.Receive("gmod.one/ai-companion/solo-request-settings", function(len, ply)
        if not game.SinglePlayer() then return end

        local npc = FindCompanion()

        if IsValid(npc) then
            local data = {
                nick = npc._customNick or "Companion",
                model = npc:GetModel(),
                combatWeapon = npc._combatWeaponClass or "weapon_smg1",
                idleWeapon = npc._idleWeaponClass or "weapon_physgun",
                healEnabled = npc._healEnabled,
                defenderMode = npc._defenderMode,
                stealthMode = npc._stealthMode or false,
                pacifistMode = npc._pacifistMode or false,
                aggressiveMode = npc._aggressiveMode or false,
            }

            net.Start("gmod.one/ai-companion/solo-send-settings")
            net.WriteString(util.TableToJSON(data))
            net.Send(ply)
            return
        end

        local SAVE_PATH = "ai_companion_data/ai_companion_solo.txt"
        if file.Exists(SAVE_PATH, "DATA") then
            local json = file.Read(SAVE_PATH, "DATA")
            if json and json ~= "" then
                local data = util.JSONToTable(json)
                if istable(data) then
                    net.Start("gmod.one/ai-companion/solo-send-settings")
                    net.WriteString(util.TableToJSON(data))
                    net.Send(ply)
                    return
                end
            end
        end

        local defaults = {
            nick = "Companion",
            model = "models/player/urban.mdl",
            combatWeapon = "weapon_smg1",
            idleWeapon = "weapon_physgun",
            healEnabled = true,
            defenderMode = true,
            stealthMode = false,
            pacifistMode = false,
            aggressiveMode = false,
        }

        net.Start("gmod.one/ai-companion/solo-send-settings")
        net.WriteString(util.TableToJSON(defaults))
        net.Send(ply)
    end)
end

concommand.Add("ai_solo_spawn", function(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end

    if not game.SinglePlayer() then
        ply:ChatPrint("[AI] Companion is only available in single-player mode!")
        return
    end

    if FindCompanion() then
        ply:ChatPrint("[AI] There's already a companion on the map! Use ai_solo_replace")
        return
    end

    local npc = ents.Create("solo_companion_npc")
    if not IsValid(npc) then
        ply:ChatPrint("[AI] Error creating NPC!")
        return
    end

    npc:SetPos(ply:GetPos() + ply:GetForward() * 50 + Vector(0, 0, 5))
    npc:Spawn()
    npc:Activate()
    ply:ChatPrint("[AI] Companion spawned!")
end)

concommand.Add("ai_solo_remove", function(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end

    local npc = FindCompanion()
    if IsValid(npc) then
        npc:Remove()
        ply:ChatPrint("[AI] Companion removed")
    else
        ply:ChatPrint("[AI] Companion not found!")
    end
end)

concommand.Add("ai_solo_replace", function(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end

    if not game.SinglePlayer() then
        ply:ChatPrint("[AI] Companion is only available in single-player mode!")
        return
    end

    local old = FindCompanion()
    if IsValid(old) then
        old:Remove()
        ply:ChatPrint("[AI] Old companion removed")
    end

    timer.Simple(0.2, function()
        if not IsValid(ply) then return end

        local npc = ents.Create("solo_companion_npc")
        if not IsValid(npc) then
            ply:ChatPrint("[AI] Error creating NPC!")
            return
        end

        npc:SetPos(ply:GetPos() + ply:GetForward() * 50 + Vector(0, 0, 5))
        npc:Spawn()
        npc:Activate()
        ply:ChatPrint("[AI] Companion recreated!")
    end)
end)

concommand.Add("ai_solo_teleport", function(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end

    local npc = FindCompanion()
    if not IsValid(npc) then
        ply:ChatPrint("[AI] Companion not found!")
        return
    end

    local tr = util.TraceLine({
        start = ply:EyePos(),
        endpos = ply:EyePos() + ply:GetAimVector() * 300,
        filter = {ply, npc}
    })

    if not tr.Hit then
        npc:SetPos(ply:GetPos() + ply:GetForward() * 50 + Vector(0, 0, 5))
        ply:ChatPrint("[AI] Companion teleported next to you")
        return
    end

    if tr.HitNormal.z > 0.7 then
        npc:SetPos(tr.HitPos + Vector(0, 0, 5))
        npc.loco:SetDesiredSpeed(0)
        npc._myTarget = nil
        npc._attackMode = false
        npc._lastKnownPos = nil
        ply:ChatPrint("[AI] Companion teleported!")
    else
        npc:SetPos(ply:GetPos() + ply:GetForward() * 50 + Vector(0, 0, 5))
        ply:ChatPrint("[AI] Can't teleport onto wall/ceiling. Companion teleported next to you.")
    end
end)

concommand.Add("ai_solo_model", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsPlayer() then return end

    local npc = FindCompanion()
    if not IsValid(npc) then
        ply:ChatPrint("[AI] Companion not found!")
        return
    end

    if #args < 1 then
        ply:ChatPrint("[AI] Usage: ai_solo_model <model_path>")
        ply:ChatPrint("[AI] Current model: " .. npc:GetModel())
        return
    end

    local model = args[1]
    if npc:SetBotModel(model) then
        npc._customModel = model
        ply:ChatPrint("[AI] Model set: " .. model)
    else
        ply:ChatPrint("[AI] Invalid model: " .. model)
    end
end)

concommand.Add("ai_solo_combat_weapon", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsPlayer() then return end

    local npc = FindCompanion()
    if not IsValid(npc) then
        ply:ChatPrint("[AI] Companion not found!")
        return
    end

    if #args < 1 then
        ply:ChatPrint("[AI] Usage: ai_solo_combat_weapon <weapon>")
        ply:ChatPrint("[AI] Supported: weapon_ar2, weapon_smg1, weapon_crossbow, weapon_shotgun, weapon_pistol, weapon_357, weapon_rpg")
        ply:ChatPrint("[AI] Current combat weapon: " .. npc._combatWeaponClass)
        return
    end

    local weapon = args[1]
    if npc:SetCombatWeapon(weapon) then
        ply:ChatPrint("[AI] Combat weapon set: " .. weapon)
    else
        ply:ChatPrint("[AI] Weapon not supported: " .. weapon)
        ply:ChatPrint("[AI] Supported: weapon_ar2, weapon_smg1, weapon_crossbow, weapon_shotgun, weapon_pistol, weapon_357, weapon_rpg")
    end
end)

concommand.Add("ai_solo_idle_weapon", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsPlayer() then return end

    local npc = FindCompanion()
    if not IsValid(npc) then
        ply:ChatPrint("[AI] Companion not found!")
        return
    end

    if #args < 1 then
        ply:ChatPrint("[AI] Usage: ai_solo_idle_weapon <weapon>")
        ply:ChatPrint("[AI] Current idle weapon: " .. npc._idleWeaponClass)
        return
    end

    local weapon = args[1]
    if npc:SetIdleWeapon(weapon) then
        ply:ChatPrint("[AI] Idle weapon set: " .. weapon)
    else
        ply:ChatPrint("[AI] Failed to set weapon: " .. weapon)
    end
end)

concommand.Add("ai_solo_heal", function(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end

    local npc = FindCompanion()
    if not IsValid(npc) then
        ply:ChatPrint("[AI] Companion not found!")
        return
    end

    npc._healEnabled = not npc._healEnabled
    npc:SaveSettings()
    if npc._healEnabled then
        ply:ChatPrint("[AI] Auto-heal ENABLED")
        ply:ChatPrint("[AI] Heal threshold: " .. math.floor(npc._healThreshold * 100) .. "% HP")
    else
        ply:ChatPrint("[AI] Auto-heal DISABLED")
        ply:ChatPrint("[AI] Current state: " .. tostring(npc._healEnabled))
    end
end)

concommand.Add("ai_solo_nick", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsPlayer() then return end

    local npc = FindCompanion()
    if not IsValid(npc) then
        ply:ChatPrint("[AI] Companion not found!")
        return
    end

    if #args < 1 then
        ply:ChatPrint("[AI] Usage: ai_solo_nick <name>")
        ply:ChatPrint("[AI] Current name: " .. npc:GetCustomNick())
        return
    end

    local name = table.concat(args, " ")
    npc:SetCustomNick(name)
    ply:ChatPrint("[AI] Name set: " .. name)
end)

concommand.Add("ai_solo_save", function(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    local npc = FindCompanion()
    if not IsValid(npc) then
        ply:ChatPrint("[AI] Companion not found!")
        return
    end
    npc:SaveSettings()
    ply:ChatPrint("[AI] Settings saved to data/ai_companion_data/ai_companion_solo.txt")
end)

concommand.Add("ai_solo_load", function(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    local npc = FindCompanion()
    if not IsValid(npc) then
        ply:ChatPrint("[AI] Companion not found!")
        return
    end
    if npc:LoadSettings() then
        ply:ChatPrint("[AI] Settings loaded from save!")
    else
        ply:ChatPrint("[AI] Save file not found!")
    end
end)

concommand.Add("ai_solo_enter_vehicle", function(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end

    local npc = FindCompanion()
    if not IsValid(npc) then
        ply:ChatPrint("[AI] Companion not found!")
        return
    end

    if npc:VehicleIsValid() then
        ply:ChatPrint("[AI] Companion is already in a vehicle!")
        return
    end

    local tr = util.TraceLine({
        start = ply:EyePos(),
        endpos = ply:EyePos() + ply:GetAimVector() * 1000,
        filter = ply
    })

    local ent = tr.Entity

    if not IsValid(ent) then
        local veh = npc:VehicleFindNearest(700)
        if IsValid(veh) then
            ent = veh
        end
    end

    if not IsValid(ent) then
        ply:ChatPrint("[AI] No vehicle found. Aim at a vehicle or stand near it.")
        return
    end

    if npc:VehicleEnter(ent) then
        ply:ChatPrint("[AI] Companion entered vehicle!")
    else
        ply:ChatPrint("[AI] Companion could not enter this vehicle.")
    end
end)

concommand.Add("ai_solo_exit_vehicle", function(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end

    local npc = FindCompanion()
    if not IsValid(npc) then
        ply:ChatPrint("[AI] Companion not found!")
        return
    end

    if not npc:VehicleIsValid() then
        ply:ChatPrint("[AI] Companion is not in a vehicle!")
        return
    end

    npc:VehicleExit()
    ply:ChatPrint("[AI] Companion exited vehicle!")
end)

concommand.Add("ai_solo_stealth", function(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    local npc = FindCompanion()
    if not IsValid(npc) then
        ply:ChatPrint("[AI] Companion not found!")
        return
    end
    npc:SetStealthMode(not npc:IsStealthMode())
    if npc:IsStealthMode() then
        ply:ChatPrint("[AI] Stealth mode ENABLED")
    else
        ply:ChatPrint("[AI] Stealth mode DISABLED")
    end
end)

concommand.Add("ai_solo_pacifist", function(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    local npc = FindCompanion()
    if not IsValid(npc) then
        ply:ChatPrint("[AI] Companion not found!")
        return
    end
    npc:SetPacifistMode(not npc:IsPacifistMode())
    if npc:IsPacifistMode() then
        ply:ChatPrint("[AI] Pacifist mode ENABLED (no attacks)")
    else
        ply:ChatPrint("[AI] Pacifist mode DISABLED")
    end
end)

concommand.Add("ai_solo_aggressive", function(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    local npc = FindCompanion()
    if not IsValid(npc) then
        ply:ChatPrint("[AI] Companion not found!")
        return
    end
    npc:SetAggressiveMode(not npc:IsAggressiveMode())
    if npc:IsAggressiveMode() then
        ply:ChatPrint("[AI] Aggressive mode ENABLED (auto-scan)")
    else
        ply:ChatPrint("[AI] Aggressive mode DISABLED")
    end
end)

concommand.Add("ai_solo_defender", function(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    local npc = FindCompanion()
    if not IsValid(npc) then
        ply:ChatPrint("[AI] Companion not found!")
        return
    end
    npc:SetDefenderMode(not npc:IsDefenderMode())
    if npc:IsDefenderMode() then
        ply:ChatPrint("[AI] Defender mode ENABLED")
    else
        ply:ChatPrint("[AI] Defender mode DISABLED")
    end
end)

concommand.Add("ai_solo_status", function(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    local npc = FindCompanion()
    if not IsValid(npc) then
        ply:ChatPrint("[AI] Companion not found!")
        return
    end

    local hp = math.Round(npc:Health()) .. "/" .. math.Round(npc:GetMaxHealth())
    local state = "idle"
    if npc:VehicleIsValid() then
        state = "in_vehicle"
    elseif npc._attackMode and IsValid(npc._myTarget) then
        state = "combat"
    elseif npc._isHealing then
        state = "healing"
    end

    local modes = {}
    if npc:IsStealthMode() then table.insert(modes, "stealth") end
    if npc:IsPacifistMode() then table.insert(modes, "pacifist") end
    if npc:IsAggressiveMode() then table.insert(modes, "aggressive") end
    if npc:IsDefenderMode() then table.insert(modes, "defender") end
    if npc:IsMedicMode() then table.insert(modes, "medic") end

    local queueSize = npc._targetQueue and #npc._targetQueue or 0
    local wep = npc:GetActiveWeapon()
    local wepName = IsValid(wep) and wep:GetClass() or "none"

    ply:ChatPrint("[AI] === Companion Status ===")
    ply:ChatPrint("[AI] Name: " .. npc:GetCustomNick())
    ply:ChatPrint("[AI] HP: " .. hp)
    ply:ChatPrint("[AI] State: " .. state)
    ply:ChatPrint("[AI] Weapon: " .. wepName)
    ply:ChatPrint("[AI] Modes: " .. (#modes > 0 and table.concat(modes, ", ") or "none"))
    ply:ChatPrint("[AI] Target queue: " .. queueSize)
    if IsValid(npc._myTarget) then
        ply:ChatPrint("[AI] Current target: " .. tostring(npc._myTarget))
    end
end)

hook.Add("PlayerSay", "gmod.one/ai-companion/solo-chat-commands", function(ply, text)
    if not game.SinglePlayer() then return end
    if not IsValid(ply) or not ply:IsPlayer() then return end

    local lowerText = string.lower(text)
    if not string.StartWith(lowerText, "!companion") then return end

    local npc = FindCompanion()
    local afterCmd = string.Trim(string.sub(text, string.len("!companion") + 1))
    if afterCmd == "" then
        ply:ChatPrint("[AI] Commands: follow, stop, attack, status, sit, standup, help")
        return ""
    end

    local args = {}
    for word in string.gmatch(afterCmd, "[^%s]+") do
        table.insert(args, word)
    end

    local cmd = string.lower(args[1] or "")

    if cmd == "follow" or cmd == "следуй" or cmd == "за мной" then
        if not IsValid(npc) then
            ply:ChatPrint("[AI] Companion not found!")
            return ""
        end
        if npc:VehicleIsValid() then npc:VehicleExit() end

        -- Включаем AI обратно
        npc._aiDisabled = false

        npc:ClearTargetQueue()
        npc._myTarget = nil
        npc._attackMode = false
        npc._lastKnownPos = nil
        ply:ChatPrint("[AI] Companion AI ENABLED - following you")
        return ""
    end

    if cmd == "stop" or cmd == "стой" or cmd == "стоп" then
        if not IsValid(npc) then
            ply:ChatPrint("[AI] Companion not found!")
            return ""
        end

        -- РАДИКАЛЬНО: Полностью отключаем AI бота
        npc._aiDisabled = true

        -- Очищаем цели бота
        npc:ClearTargetQueue()
        npc._myTarget = nil
        npc._attackMode = false
        npc._lastKnownPos = nil
        npc.loco:SetDesiredSpeed(0)

        -- Очищаем память мастера
        if IsValid(ply) then
            ply._lastAttacker = nil
            ply._lastPlayerTarget = nil
        end

        ply:ChatPrint("[AI] Companion AI DISABLED - standing still")
        return ""
    end

    if cmd == "attack" or cmd == "атакуй" then
        if not IsValid(npc) then
            ply:ChatPrint("[AI] Companion not found!")
            return ""
        end
        if npc:IsPacifistMode() then
            ply:ChatPrint("[AI] Pacifist mode is active!")
            return ""
        end

        if args[2] then
            local targetName = table.concat(args, " ", 2)
            local target = nil
            for _, p in ipairs(player.GetAll()) do
                if string.find(string.lower(p:Nick()), string.lower(targetName), 1, true) then
                    target = p
                    break
                end
            end

            if IsValid(target) then
                npc:RequestTarget(target, "command_llm", true)
                ply:ChatPrint("[AI] Attacking: " .. target:Nick())
            else
                ply:ChatPrint("[AI] Player not found: " .. targetName)
            end
        else
            local myPos = npc:GetPos()
            local bestEnemy = nil
            local bestDist = 2000

            for _, ent in ipairs(ents.FindInSphere(myPos, 2000)) do
                if IsValid(ent) and ent ~= npc then
                    if ent:IsNPC() or ent:IsNextBot() then
                        if not npc:IsFriendlyEntity(ent) and npc:IsTargetAlive(ent) then
                            local d = myPos:Distance(ent:GetPos())
                            if d < bestDist then
                                bestDist = d
                                bestEnemy = ent
                            end
                        end
                    end
                end
            end

            if IsValid(bestEnemy) then
                npc:RequestTarget(bestEnemy, "command", true)
                ply:ChatPrint("[AI] Attacking nearest enemy!")
            else
                ply:ChatPrint("[AI] No enemies found nearby")
            end
        end
        return ""
    end

    if cmd == "sit" or cmd == "сядь" or cmd == "садись" then
        if not IsValid(npc) then
            ply:ChatPrint("[AI] Companion not found!")
            return ""
        end
        if npc:VehicleIsValid() then
            ply:ChatPrint("[AI] Already in a vehicle!")
            return ""
        end

        local veh = npc:VehicleFindNearest(700)
        if IsValid(veh) then
            if npc:VehicleEnter(veh) then
                ply:ChatPrint("[AI] Companion entered vehicle!")
            else
                ply:ChatPrint("[AI] Could not enter vehicle")
            end
        else
            ply:ChatPrint("[AI] No vehicle found nearby")
        end
        return ""
    end

    if cmd == "standup" or cmd == "встань" or cmd == "вставай" then
        if not IsValid(npc) then
            ply:ChatPrint("[AI] Companion not found!")
            return ""
        end
        if npc:VehicleIsValid() then
            npc:VehicleExit()
        end
        ply:ChatPrint("[AI] Companion stood up")
        return ""
    end

    if cmd == "status" or cmd == "статус" then
        if not IsValid(npc) then
            ply:ChatPrint("[AI] Companion not found!")
            return ""
        end
        ply:ConCommand("ai_solo_status")
        return ""
    end

    if cmd == "help" or cmd == "помощь" then
        ply:ChatPrint("[AI] === Companion Commands ===")
        ply:ChatPrint("[AI] !companion follow - Follow me")
        ply:ChatPrint("[AI] !companion stop - Stop moving")
        ply:ChatPrint("[AI] !companion attack [name] - Attack target")
        ply:ChatPrint("[AI] !companion sit - Enter nearest vehicle")
        ply:ChatPrint("[AI] !companion standup - Exit vehicle")
        ply:ChatPrint("[AI] !companion status - Show status")
        ply:ChatPrint("[AI] !companion help - This help")
        return ""
    end

    return nil
end)
