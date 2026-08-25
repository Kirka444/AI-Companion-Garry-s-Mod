if AI_COMPANION_CORE_LOADED_v20 then return end
AI_COMPANION_CORE_LOADED_v20 = true
local AC = _G.AI_COMPANION
if not AC or not AC._is_ai_companion then
    ErrorNoHalt("[AI Core] ОШИБКА: _G.AI_COMPANION не инициализирован!\n")
    ErrorNoHalt("[AI Core] Убедитесь, что ai_companion_state.lua загружен первым.\n")
    return
end
if AC._version ~= "2.0.0" then
    ErrorNoHalt("[AI Core] ВНИМАНИЕ: Несовместимая версия хранилища!\n")
    ErrorNoHalt("[AI Core] Ожидается: 2.0.0, получено: " .. tostring(AC._version) .. "\n")
end
if not AC.Utils then
    local ok, err = pcall(include, "ai_companion/ai_companion_utils.lua")
    if not ok then
        ErrorNoHalt("[AI Core] Не удалось загрузить ai_companion_utils.lua: " .. tostring(err) .. "\n")
        return
    end
end
if not AC.Config then
    local ok, err = pcall(include, "ai_companion/ai_config.lua")
    if not ok then
        ErrorNoHalt("[AI Core] Не удалось загрузить ai_config.lua: " .. tostring(err) .. "\n")
        return
    end
end
if AC.State then
    AC.State.TTS_Enabled = AC.State.TTS_Enabled or false
    AC.State.TTS_Global = AC.State.TTS_Global or false
    AC.State.LLM_Enabled = AC.State.LLM_Enabled or true
    AC.State.Disabled = AC.State.Disabled or false
end
local Companion = AC.Companion or {}
local States = Companion.States or {}
local ValidTransitions = Companion.ValidTransitions or {}
function IsBotSafe(ent)
    if not IsValid(ent) then return false end
    if not ent.IsPlayer then return false end
    local ok, res = pcall(ent.IsPlayer, ent)
    if not ok or not res then return false end
    ok, res = pcall(ent.IsBot, ent)
    return ok and res
end
function IsPlayerSafe(ent)
    if not IsValid(ent) then return false end
    if not ent.IsPlayer then return false end
    local ok, res = pcall(ent.IsPlayer, ent)
    if not ok or not res then return false end
    ok, res = pcall(ent.IsBot, ent)
    return ok and not res
end
function IsHostileEntity(ent)
    if not AC.Utils or not AC.Utils.IsValid(ent) then return false end
    local okAlive, alive = pcall(function() return ent:Alive() end)
    if okAlive and not alive then return false end
    local okClass, class = pcall(function() return ent:GetClass() end)
    if not okClass then return false end
    local FriendlyNPCs = Companion.FriendlyNPCs or {}
    if FriendlyNPCs[class] then return false end
    if IsBotSafe(ent) then
        if ent:GetNWBool("IsAICompanion", false) then
            return false
        end
        return true
    end
    if IsPlayerSafe(ent) then
        local bot = GetCompanion()
        if AC.Utils and AC.Utils.IsValid(bot) then
            local data = GetBotData(bot)
            local owner = data and data.owner
            if IsValid(owner) and owner == ent then return false end
        end
        return true
    end
    if ent:IsNPC() or ent:IsNextBot() then
        return true
    end
    if string.find(string.lower(class), "npc") and not string.find(class, "npc_%w+_friendly") then
        return true
    end
    return false
end
if not _G.ApplyWorldMovement then
    _G.ApplyWorldMovement = function(cmd, moveVec, speed)
        if not cmd then return end
        if moveVec:LengthSqr() <= 1e-4 then return end
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
function URLEncode(str)
    if not str then return "" end
    return string.gsub(str, "([^%w%-_%.%!%*%'%(%)])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
end
hook.Add("PlayerDeath", "AI_Core_Cleanup_Death", function(victim)
    if not AC.Utils or not AC.Utils.IsValid(victim) then return end
    if not victim:IsBot() then return end
    if not victim:GetNWBool("IsAICompanion", false) then return end
    if victim._aiDeathCleanupDone then return end
    victim._aiDeathCleanupDone = true
    if _G.UnregisterCompanionBot then
        _G.UnregisterCompanionBot(victim, "Погиб", true)
    end
end)
hook.Add("PlayerDisconnected", "AI_RemoveCompanionOnDisconnect", function(ply)
    if not AC.Utils or not AC.Utils.IsValid(ply) then return end
    if ply:IsBot() and ply:GetNWBool("IsAICompanion", false) then
        if ply._aiCleanupDone then return end
        ply._aiCleanupDone = true
        if _G.UnregisterCompanionBot then
            _G.UnregisterCompanionBot(ply, "Отключился", true)
        end
        return
    end
    if ply:IsPlayer() and not ply:IsBot() then
        if _G.BotManager then
            _G.BotManager:RemoveAllBots(ply, "Владелец вышел")
        end
    end
end)
local lastRestoreCheck = 0
hook.Add("Think", "AICompanion_RestoreOwner", function()
    if CurTime() - lastRestoreCheck < 2 then return end
    lastRestoreCheck = CurTime()
    if not _G.BotManager then return end
    _G.BotManager:Cleanup()
    for _, bot in ipairs(_G.BotManager:GetAllBots()) do
        if IsValid(bot) then
            if _G.BotManager.SyncToNWVars then
                _G.BotManager:SyncToNWVars(bot)
            end
        end
    end
end)
if SERVER then
    util.AddNetworkString("AICompanion_RequestConfig")
    util.AddNetworkString("AICompanion_ConfigSync")
    util.AddNetworkString("AICompanion_OwnerSync")
    util.AddNetworkString("AICompanion_ColorSync")
    net.Receive("AICompanion_RequestConfig", function(len, ply)
        if not AC.Utils or not AC.Utils.IsValid(ply) then return end
        local settings = nil
        if GetPlayerSettings then
            settings = GetPlayerSettings(ply)
        end
        if not settings then
            settings = AC.Settings
        end
        local bot = _G.BotManager and _G.BotManager:GetBotByOwner(ply) or nil
        local botData = IsValid(bot) and GetBotData(bot) or nil
        local LLM_IP = AC.Settings.LLM_IP or "localhost"
        local LLM_Port = AC.Settings.LLM_Port or 1234
        local LLM_Model = AC.Settings.LLM_Model or "local-model"
        local TTS_IP = AC.Settings.TTS_IP or "localhost"
        local TTS_Port = AC.Settings.TTS_Port or 8188
        local Prefix_Text = AC.Settings.Prefix_Text or "[AI]"
        local Prefix_Color_R = AC.Settings.Prefix_Color_R or 255
        local Prefix_Color_G = AC.Settings.Prefix_Color_G or 200
        local Prefix_Color_B = AC.Settings.Prefix_Color_B or 0
        local Prefix_Rainbow = AC.Settings.Prefix_Rainbow or false
        local Debug_Mode = AC.Settings.Debug_Mode or false
        local TTS_Enabled = AC.State.TTS_Enabled or false
        local LLM_Enabled = AC.State.LLM_Enabled or true
        local StealthMode = AC.State.StealthMode or false
        local DefenderMode = AC.State.DefenderMode or false
        local MedicMode = AC.State.MedicMode or false
        local PacifistMode = AC.State.PacifistMode or false
        local AggressiveMode = AC.State.AggressiveMode or false
        net.Start("AICompanion_ConfigSync")
        net.WriteString(settings.companion_nick or AC.Settings.Companion_Nick or "AI_Companion")
        net.WriteString(settings.model_path or AC.Settings.Model_Path or "models/player/urban.mdl")
        net.WriteString(botData and botData.config.combat_weapon or settings.combat_weapon or AC.Settings.Combat_Weapon or "weapon_smg1")
        net.WriteString(botData and botData.config.melee_weapon or settings.melee_weapon or AC.Settings.Melee_Weapon or "weapon_crowbar")
        net.WriteString(botData and botData.config.idle_weapon or settings.idle_weapon or AC.Settings.Idle_Weapon or "weapon_physgun")
        net.WriteBool(botData and botData.config.stealth_mode or settings.stealth_mode or StealthMode)
        net.WriteBool(botData and botData.config.defender_mode or settings.defender_mode or DefenderMode)
        net.WriteBool(botData and botData.config.medic_mode or settings.medic_mode or MedicMode)
        net.WriteBool(botData and botData.config.pacifist_mode or settings.pacifist_mode or PacifistMode)
        net.WriteBool(botData and botData.config.aggressive_mode or settings.aggressive_mode or AggressiveMode)
        net.WriteBool(AC.Config and AC.Config.DEBUG_MODE or Debug_Mode)
        net.WriteBool(TTS_Enabled)
        net.WriteBool(LLM_Enabled)
        net.WriteString(LLM_IP)
        net.WriteUInt(LLM_Port, 16)
        net.WriteString(LLM_Model)
        net.WriteString(TTS_IP)
        net.WriteUInt(TTS_Port, 16)
        net.WriteString(settings.prefix_text or Prefix_Text)
        net.WriteUInt(settings.prefix_r or Prefix_Color_R, 8)
        net.WriteUInt(settings.prefix_g or Prefix_Color_G, 8)
        net.WriteUInt(settings.prefix_b or Prefix_Color_B, 8)
        net.WriteBool(settings.prefix_rainbow or Prefix_Rainbow)
        net.Send(ply)
    end)
end
if CLIENT then
    net.Receive("AICompanion_OwnerSync", function()
        local bot = net.ReadEntity()
        local owner = net.ReadEntity()
        if IsValid(bot) and IsValid(owner) then
            bot:SetNWEntity("AICompanionOwnerEnt", owner)
            bot:SetNWString("AICompanionOwner", owner:Nick())
        end
    end)
    net.Receive("AICompanion_ConfigSync", function()
        if not IsValid(_G.AICompanionMenuPanel) then return end
        local nick = net.ReadString()
        local model = net.ReadString()
        local combatWep = net.ReadString()
        local meleeWep = net.ReadString()
        local idleWep = net.ReadString()
        local stealth = net.ReadBool()
        local defender = net.ReadBool()
        local medic = net.ReadBool()
        local pacifist = net.ReadBool()
        local aggressive = net.ReadBool()
        local debug = net.ReadBool()
        local ttsEnabled = net.ReadBool()
        local llmEnabled = net.ReadBool()
        local llmIP = net.ReadString()
        local llmPort = net.ReadUInt(16)
        local llmModel = net.ReadString()
        local ttsIP = net.ReadString()
        local ttsPort = net.ReadUInt(16)
        local prefixText = net.ReadString()
        local prefixR = net.ReadUInt(8)
        local prefixG = net.ReadUInt(8)
        local prefixB = net.ReadUInt(8)
        local prefixRainbow = net.ReadBool()
        AC.Settings.Model_Path = model
        AC.Settings.Companion_Nick = nick
        AC.State.TTS_Enabled = ttsEnabled
        AC.State.LLM_Enabled = llmEnabled
        AC.Settings.LLM_IP = llmIP
        AC.Settings.LLM_Port = llmPort
        AC.Settings.LLM_Model = llmModel
        AC.Settings.TTS_IP = ttsIP
        AC.Settings.TTS_Port = ttsPort
        AC.Settings.Prefix_Text = prefixText
        AC.Settings.Prefix_Color_R = prefixR
        AC.Settings.Prefix_Color_G = prefixG
        AC.Settings.Prefix_Color_B = prefixB
        AC.Settings.Prefix_Rainbow = prefixRainbow
        _G.CurrentCompanionModel = model
        _G.AI_COMPANION_NICK = nick
        _G.AI_Companion_TTS_Enabled = ttsEnabled
        _G.AI_Companion_LLM_Enabled = llmEnabled
        _G.AI_LLM_IP = llmIP
        _G.AI_LLM_PORT = llmPort
        _G.AI_LLM_MODEL = llmModel
        _G.AI_COMFYUI_IP = ttsIP
        _G.AI_COMFYUI_PORT = ttsPort
        _G.AI_Companion_PrefixText = prefixText
        _G.AI_Companion_PrefixColorR = prefixR
        _G.AI_Companion_PrefixColorG = prefixG
        _G.AI_Companion_PrefixColorB = prefixB
        _G.AI_Companion_PrefixRainbow = prefixRainbow
        if AC.Config then
            AC.Config.DEBUG_MODE = debug
        end
        if _G.AI_SETTINGS then
            _G.AI_SETTINGS.companion_nick = nick
            _G.AI_SETTINGS.model_path = model
            _G.AI_SETTINGS.combat_weapon = combatWep
            _G.AI_SETTINGS.melee_weapon = meleeWep
            _G.AI_SETTINGS.idle_weapon = idleWep
            _G.AI_SETTINGS.stealth_mode = stealth
            _G.AI_SETTINGS.defender_mode = defender
            _G.AI_SETTINGS.medic_mode = medic
            _G.AI_SETTINGS.pacifist_mode = pacifist
            _G.AI_SETTINGS.aggressive_mode = aggressive
            _G.AI_SETTINGS.llm_ip = llmIP
            _G.AI_SETTINGS.llm_port = llmPort
            _G.AI_SETTINGS.llm_model = llmModel
            _G.AI_SETTINGS.comfyui_ip = ttsIP
            _G.AI_SETTINGS.comfyui_port = ttsPort
            _G.AI_SETTINGS.tts_enabled = ttsEnabled
            _G.AI_SETTINGS.llm_enabled = llmEnabled
            _G.AI_SETTINGS.debug_mode = debug
            _G.AI_SETTINGS.prefix_text = prefixText
            _G.AI_SETTINGS.prefix_r = prefixR
            _G.AI_SETTINGS.prefix_g = prefixG
            _G.AI_SETTINGS.prefix_b = prefixB
            _G.AI_SETTINGS.prefix_rainbow = prefixRainbow
        end
        if _G.AICompanionMenuPanel and _G.AICompanionMenuPanel.RefreshValues then
            _G.AICompanionMenuPanel:RefreshValues()
        end
    end)
end
timer.Create("AI_CacheCleanup", 300, 0, function()
    if AC.Cache then
        if AC.Cache.LLM and AC.Cache.LLM.cleanup then
            AC.Cache.LLM:cleanup()
        end
        if AC.Cache.TTS and AC.Cache.TTS.cleanup then
            AC.Cache.TTS:cleanup()
        end
    end
end)
concommand.Add("ai_test_hostile", function(ply)
    if not IsValid(ply) or not ply:IsAdmin() then
        if IsValid(ply) then
            ply:ChatPrint("[AI] Только администраторы!")
        end
        return
    end
    print("")
    print("═══════════════════════════════════════════════════════")
    print("        AI CORE - ПРОВЕРКА ФУНКЦИЙ")
    print("═══════════════════════════════════════════════════════")
    print("")
    if AI_Utils and AI_Utils.LogInfo then
        AI_Utils.LogInfo("Core", "AC._is_ai_companion: %s", tostring(AC._is_ai_companion))
        AI_Utils.LogInfo("Core", "AC._version: %s", tostring(AC._version))
        AI_Utils.LogInfo("Core", "AC.State.TTS_Enabled: %s", tostring(AC.State.TTS_Enabled))
        AI_Utils.LogInfo("Core", "AC.State.LLM_Enabled: %s", tostring(AC.State.LLM_Enabled))
        AI_Utils.LogInfo("Core", "AC.Settings.LLM_IP: %s", tostring(AC.Settings.LLM_IP))
        AI_Utils.LogInfo("Core", "AC.Settings.TTS_IP: %s", tostring(AC.Settings.TTS_IP))
        AI_Utils.LogInfo("Core", "IsBotSafe(ply): %s", tostring(IsBotSafe(ply)))
    else
        print("  AC._is_ai_companion: " .. tostring(AC._is_ai_companion))
        print("  AC._version: " .. tostring(AC._version))
        print("  AC.State.TTS_Enabled: " .. tostring(AC.State.TTS_Enabled))
        print("  AC.State.LLM_Enabled: " .. tostring(AC.State.LLM_Enabled))
        print("  AC.Settings.LLM_IP: " .. tostring(AC.Settings.LLM_IP))
        print("  AC.Settings.TTS_IP: " .. tostring(AC.Settings.TTS_IP))
        print("  IsBotSafe(ply): " .. tostring(IsBotSafe(ply)))
    end
    local target = ply:GetEyeTrace().Entity
    if IsValid(target) then
        if AI_Utils and AI_Utils.LogInfo then
            AI_Utils.LogInfo("Core", "Цель прицела: %s", tostring(target))
            AI_Utils.LogInfo("Core", "IsPlayerSafe(target): %s", tostring(IsPlayerSafe(target)))
            AI_Utils.LogInfo("Core", "IsBotSafe(target): %s", tostring(IsBotSafe(target)))
            AI_Utils.LogInfo("Core", "IsHostileEntity(target): %s", tostring(IsHostileEntity(target)))
            AI_Utils.LogInfo("Core", "Класс: %s", target:GetClass() or "неизвестно")
        else
            print("  Цель прицела: " .. tostring(target))
            print("  IsPlayerSafe(target): " .. tostring(IsPlayerSafe(target)))
            print("  IsBotSafe(target): " .. tostring(IsBotSafe(target)))
            print("  IsHostileEntity(target): " .. tostring(IsHostileEntity(target)))
            print("  Класс: " .. (target:GetClass() or "неизвестно"))
        end
    else
        if AI_Utils and AI_Utils.LogInfo then
            AI_Utils.LogInfo("Core", "Нет цели прицела")
        else
            print("  Нет цели прицела")
        end
    end
    print("")
    print("═══════════════════════════════════════════════════════")
    print("")
    if IsValid(ply) then
        ply:ChatPrint("[AI] Результаты проверки в консоли")
    end
end)
concommand.Add("ai_diagnostic", function(ply)
    if not IsValid(ply) or not ply:IsAdmin() then
        if IsValid(ply) then
            ply:ChatPrint("[AI] Только администраторы!")
        end
        return
    end
    if AC.Diagnostic then
        AC.Diagnostic()
    else
        if AI_Utils and AI_Utils.LogWarn then
            AI_Utils.LogWarn("Core", "Функция диагностики не найдена")
        else
            print("[AI] Функция диагностики не найдена")
        end
    end
    if IsValid(ply) then
        ply:ChatPrint("[AI] Диагностика выведена в консоль")
    end
end)
_G.IsBotSafe = IsBotSafe
_G.IsPlayerSafe = IsPlayerSafe
_G.IsHostileEntity = IsHostileEntity
_G.URLEncode = URLEncode
if AI_Utils and AI_Utils.LogInfo then
    AI_Utils.LogInfo("Core", "v20 загружен (без дублирования глобальных функций, унифицированное логирование)")
    AI_Utils.LogInfo("Core", "Версия хранилища: %s", tostring(AC._version))
else
    print("[AI Core] v20 загружен (без дублирования глобальных функций, унифицированное логирование)")
    print("[AI Core] Версия хранилища: " .. tostring(AC._version))
end