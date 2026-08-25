if AI_COMPANION_CLIENT_LOADED then return end
AI_COMPANION_CLIENT_LOADED = true
if not CLIENT then return end
local AC = _G.AI_COMPANION
if not AI_Utils then
    include("ai_companion/ai_companion_utils.lua")
end
local AVATAR_PNG = "ai_companion/avatar.png"
local AVATAR_MAT = nil
local AVATAR_PRELOADED = false
local function GetAvatarMat()
    if AVATAR_MAT and not AVATAR_MAT:IsError() then
        return AVATAR_MAT
    end
    AVATAR_MAT = Material(AVATAR_PNG, "smooth mips")
    if AVATAR_MAT:IsError() then
        AVATAR_MAT = Material("ai_companion/avatar.jpg", "smooth mips")
    end
    return AVATAR_MAT
end
local function PreloadAvatar()
    if AVATAR_PRELOADED then return end
    local preload = vgui.Create("DPanel")
    preload:SetSize(1, 1)
    preload:SetPos(-100, -100)
    preload.Paint = function(self, w, h)
        if not AVATAR_MAT then
            AVATAR_MAT = GetAvatarMat()
            if AVATAR_MAT and not AVATAR_MAT:IsError() then
                AVATAR_PRELOADED = true
            end
        end
    end
    timer.Simple(0.1, function()
        if IsValid(preload) then preload:Remove() end
    end)
end
hook.Add("InitPostEntity", "AICompanion_PreloadAvatar", function()
    PreloadAvatar()
end)
hook.Add("InitPostEntity", "AICompanion_ShowProfile", function()
    local meta = FindMetaTable("Player")
    if not meta then return end
    local old_ShowProfile = meta.ShowProfile
    meta.ShowProfile = function(self)
        if self:GetNWBool("IsAICompanion", false) then
            return
        end
        if old_ShowProfile then
            return old_ShowProfile(self)
        end
    end
end)
local function ApplyAvatarOverride(entry)
    if not IsValid(entry) then return false end
    if not IsValid(entry.Player) then return false end
    if not entry.Player:GetNWBool("IsAICompanion", false) then return false end
    local mat = GetAvatarMat()
    if not mat or mat:IsError() then return false end
    entry.Avatar.PaintOver = function(self, w, h)
        surface.SetDrawColor(255, 255, 255)
        surface.SetMaterial(mat)
        surface.DrawTexturedRect(0, 0, w, h)
    end
    if IsValid(entry.AvatarButton) then
        entry.AvatarButton.DoClick = function() end
    end
    return true
end
hook.Add("ScoreboardPlayerRowCreated", "AICompanion_AvatarOnRowCreate", function(panel, ply)
    if not IsValid(ply) or not IsValid(panel) then return end
    if ply:GetNWBool("IsAICompanion", false) then
        timer.Simple(0.1, function()
            if IsValid(panel) and IsValid(panel.Player) and panel.Player == ply then
                ApplyAvatarOverride(panel)
            end
        end)
    end
end)
hook.Add("ScoreboardShow", "AICompanion_AvatarFallback", function()
    timer.Simple(0.1, function()
        for _, pl in ipairs(player.GetAll()) do
            if IsValid(pl.ScoreEntry) then
                ApplyAvatarOverride(pl.ScoreEntry)
            end
        end
    end)
end)
local function GetClientPrefixColor()
    local ply = LocalPlayer()
    if not IsValid(ply) then return Color(255, 200, 0) end
    local settings = nil
    if GetPlayerSettings then
        settings = GetPlayerSettings(ply)
    end
    if not settings then
        settings = AI_SETTINGS
    end
    if not settings then
        return Color(255, 200, 0)
    end
    if settings.prefix_rainbow then
        local hue = (CurTime() * 120) % 360
        return HSVToColor(hue, 1, 1)
    end
    return Color(
        settings.prefix_r or 255,
        settings.prefix_g or 200,
        settings.prefix_b or 0
    )
end
local function GetClientCleanPrefix()
    local ply = LocalPlayer()
    if not IsValid(ply) then return "AI" end
    local settings = nil
    if GetPlayerSettings then
        settings = GetPlayerSettings(ply)
    end
    if not settings then
        settings = AI_SETTINGS
    end
    if not settings then
        return "AI"
    end
    local prefix = settings.prefix_text or "[AI]"
    local clean = string.gsub(prefix, "^%[", "")
    clean = string.gsub(clean, "%]$", "")
    clean = string.Trim(clean)
    if clean == "" then clean = "AI" end
    return clean
end
net.Receive("AI_Companion_PlayAudio", function()
    local url = net.ReadString()
    if not url or url == "" then
        if AI_Utils and AI_Utils.LogDebug then
            AI_Utils.LogDebug("Client", "Пустой URL для TTS")
        end
        return
    end
    if AI_Utils and AI_Utils.LogDebug then
        AI_Utils.LogDebug("Client", "TTS URL: %s", url)
    end
    if not file.Exists("ai_companion_cache", "DATA") then
        file.CreateDir("ai_companion_cache")
    end
    local fileName = "ai_tts_" .. os.time() .. "_" .. math.random(1000, 9999) .. ".mp3"
    local cachePath = "ai_companion_cache/" .. fileName
    http.Fetch(url,
        function(body, size, headers, code)
            if code ~= 200 or not body or #body < 100 then
                if AI_Utils and AI_Utils.LogWarn then
                    AI_Utils.LogWarn("Client", "Ошибка загрузки TTS: код %d, размер %d", code, size)
                end
                chat.AddText(Color(255,100,100), "[AI] Ошибка загрузки голоса")
                return
            end
            if AI_Utils and AI_Utils.LogDebug then
                AI_Utils.LogDebug("Client", "TTS скачан: %d байт", #body)
            end
            file.Write(cachePath, body)
            local fullPath = "data/" .. cachePath
            sound.PlayFile(fullPath, "mono", function(station, err)
                if IsValid(station) and not err then
                    station:SetVolume(1.0)
                    station:Play()
                    if AI_Utils and AI_Utils.LogDebug then
                        AI_Utils.LogDebug("Client", "TTS воспроизводится")
                    end
                    local lifetime = (AI_CONFIG and AI_CONFIG.TTS and AI_CONFIG.TTS.AudioCacheLifetime) or 30
                    timer.Simple(lifetime, function()
                        if file.Exists(cachePath, "DATA") then
                            file.Delete(cachePath)
                        end
                    end)
                else
                    if AI_Utils and AI_Utils.LogWarn then
                        AI_Utils.LogWarn("Client", "Ошибка воспроизведения TTS: %s", tostring(err))
                    end
                    chat.AddText(Color(255,100,100), "[AI] Ошибка воспроизведения: " .. tostring(err))
                end
            end)
        end,
        function(err)
            if AI_Utils and AI_Utils.LogError then
                AI_Utils.LogError("Client", "Ошибка http.Fetch для TTS: %s", tostring(err))
            end
            chat.AddText(Color(255,100,100), "[AI] Не удалось скачать голос")
        end
    )
end)
net.Receive("AI_Companion_Private_Chat", function()
    local text = net.ReadString()
    local color = net.ReadColor() 
    local senderName = net.ReadString() or "AI"
    local receiverName = net.ReadString() or "Игрок"
    local receiverSteamID = net.ReadString() or ""
    if not text or text == "" then return end
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    if receiverSteamID ~= "" and receiverSteamID ~= ply:SteamID64() then
        return
    end
    local prefixColor = GetClientPrefixColor()
    local cleanPrefix = GetClientCleanPrefix()
    local isFromAI = (senderName == "AI" or 
                      senderName == cleanPrefix or 
                      senderName == "[AI]" or
                      string.find(senderName, "^" .. cleanPrefix) or
                      string.find(senderName, cleanPrefix .. "$"))
    if isFromAI then
        chat.AddText(prefixColor, "Приват: [" .. cleanPrefix .. " -> " .. receiverName .. "] ", Color(255,255,255), text)
    else
        chat.AddText(prefixColor, "Приват: [" .. senderName .. " -> " .. cleanPrefix .. "] ", Color(255,255,255), text)
    end
end)
net.Receive("AI_Companion_Chat", function()
    local success, err = pcall(function()
        local text = net.ReadString()
        local color = net.ReadColor()
        local senderName = net.ReadString() or "AI"
        local receiverName = "Игрок"
        if net.BytesLeft() > 0 then
            receiverName = net.ReadString() or "Игрок"
        end
        local receiverSteamID = ""
        if net.BytesLeft() > 0 then
            receiverSteamID = net.ReadString() or ""
        end
        if not text or text == "" then return end
        local ply = LocalPlayer()
        if not IsValid(ply) then return end
        if receiverSteamID ~= "" and receiverSteamID ~= ply:SteamID64() then
            return
        end
        local prefixColor = GetClientPrefixColor()
        local cleanPrefix = GetClientCleanPrefix()
        local showName = true
        if IsValid(ply) and GetPlayerSettings then
            local settings = GetPlayerSettings(ply)
            if settings and settings.show_sender_name ~= nil then
                showName = settings.show_sender_name
            end
        end
        local isFromAI = (senderName == "AI" or 
                          senderName == cleanPrefix or 
                          senderName == "[AI]" or
                          string.find(senderName, "^" .. cleanPrefix) or
                          string.find(senderName, cleanPrefix .. "$"))
        local statusPatterns = {
            "Думаю", "Печата", "Обрабатыв", "Готовлю", "Загружаю",
            "Ожидаю", "Размышляю", "Думает", "Жду", "Слушаю"
        }
        local isStatus = false
        for _, pattern in ipairs(statusPatterns) do
            if string.find(text, pattern) then
                isStatus = true
                break
            end
        end
        local words = {}
        for w in string.gmatch(text, "%S+") do
            table.insert(words, w)
        end
        if #words == 1 then
            for _, pattern in ipairs(statusPatterns) do
                if string.find(text, pattern) then
                    isStatus = true
                    break
                end
            end
        end
        if isFromAI then
            if isStatus then
                chat.AddText(prefixColor, "[" .. cleanPrefix .. "] ", Color(255,255,255), text)
            elseif showName then
                local fullPrefix = "[" .. cleanPrefix .. " -> " .. receiverName .. "] "
                chat.AddText(prefixColor, fullPrefix, Color(255,255,255), text)
            else
                chat.AddText(prefixColor, "[" .. cleanPrefix .. "] ", Color(255,255,255), text)
            end
        else
            if showName then
                local fullPrefix = "[" .. cleanPrefix .. " -> " .. senderName .. "] "
                chat.AddText(prefixColor, fullPrefix, Color(255,255,255), text)
            else
                chat.AddText(prefixColor, "[" .. cleanPrefix .. "] ", Color(255,255,255), text)
            end
        end
    end)
    if not success then
        if AI_Utils and AI_Utils.LogWarn then
            AI_Utils.LogWarn("Client", "AI_Companion_Chat: ошибка чтения: %s", tostring(err))
        else
            print("[AI Client] Ошибка чтения AI_Companion_Chat:", tostring(err))
        end
    end
end)
local function GetClientPrefixSettings()
    local ply = LocalPlayer()
    local settings = {
        text = "[AI]",
        r = 255,
        g = 200,
        b = 0,
        rainbow = false
    }
    if IsValid(ply) and GetPlayerSettings then
        local plySettings = GetPlayerSettings(ply)
        if plySettings then
            settings.text = plySettings.prefix_text or "[AI]"
            settings.r = plySettings.prefix_r or 255
            settings.g = plySettings.prefix_g or 200
            settings.b = plySettings.prefix_b or 0
            settings.rainbow = plySettings.prefix_rainbow or false
        end
    end
    if not settings.rainbow then
        settings.rainbow = _G.AI_Companion_PrefixRainbow or false
    end
    return settings
end
concommand.Add("ai_avatar_check", function()
    local mat = GetAvatarMat()
    if mat and not mat:IsError() then
        chat.AddText(Color(0,255,0), "[AI] Аватарка загружена")
    else
        chat.AddText(Color(255,0,0), "[AI] Аватарка не найдена!")
    end
end)
concommand.Add("ai_avatar_force", function()
    local mat = GetAvatarMat()
    if not mat or mat:IsError() then
        chat.AddText(Color(255,0,0), "[AI] Материал не загружен")
        return
    end
    local count = 0
    for _, pl in ipairs(player.GetAll()) do
        if ApplyAvatarOverride(pl.ScoreEntry) then
            count = count + 1
        end
    end
    chat.AddText(Color(0,255,0), "[AI] Аватарка установлена для " .. count .. " ботов")
end)
concommand.Add("ai_tts_test_local", function()
    sound.PlayFile("data/ai_companion_cache/test.mp3", "mono", function(station, err)
        if IsValid(station) and not err then
            station:Play()
            if AI_DebugPrint then
                AI_DebugPrint("[AI TTS TEST] OK!")
            end
        else
            if AI_DebugPrint then
                AI_DebugPrint("[AI TTS TEST] ERROR:", err)
            end
        end
    end)
end)
net.Receive("AICompanion_ColorSync", function()
    local bot = net.ReadEntity()
    local color = net.ReadVector()
    if IsValid(bot) then
        pcall(function()
            if bot.SetWeaponColor then
                bot:SetWeaponColor(color)
            end
        end)
    end
end)
net.Receive("AICompanion_OwnerSync", function()
    local bot = net.ReadEntity()
    local owner = net.ReadEntity()
    if IsValid(bot) and IsValid(owner) then
        bot:SetNWEntity("AICompanionOwnerEnt", owner)
        bot:SetNWString("AICompanionOwner", owner:Nick())
        if BotManager and BotManager.GetData then
            local data = BotManager:GetData(bot)
            if data then
                data.owner = owner
                if BotManager.UpdateData then
                    BotManager:UpdateData(bot, data)
                end
            end
        end
        if AI_Companion then
            AI_Companion.OwnerToBot = AI_Companion.OwnerToBot or {}
            AI_Companion.OwnerToBot[owner] = bot
            AI_Companion.BotOwners = AI_Companion.BotOwners or {}
            AI_Companion.BotOwners[bot:EntIndex()] = owner
        end
        if IsValid(_G.AICompanionMenuPanel) then
            _G.AICompanionMenuPanel:RefreshBotStatus()
        end
    end
end)
net.Receive("AI_Settings_Sync", function()
    if game.SinglePlayer() then
        if AI_LoadSettings then
            AI_LoadSettings()
        end
        if AI_ApplySettings then
            AI_ApplySettings()
        end
        if IsValid(_G.AICompanionMenuPanel) then
            pcall(function()
                if _G.AICompanionMenuPanel.RefreshValues then
                    _G.AICompanionMenuPanel:RefreshValues()
                end
            end)
        end
        return
    end
    local rawData = net.ReadString()
    if AI_CONFIG and AI_CONFIG.DEBUG_MODE then
        print("[AI DEBUG] Получено данных: " .. tostring(#rawData) .. " байт")
        print("[AI DEBUG] Первые 100 символов: " .. string.sub(tostring(rawData), 1, 100))
    end
    if not rawData or rawData == "" then
        if AI_CONFIG and AI_CONFIG.DEBUG_MODE then
            print("[AI DEBUG] ОШИБКА: пустые данные!")
        end
        return
    end
    local ok, tbl = pcall(util.JSONToTable, rawData)
    if not ok then
        if AI_CONFIG and AI_CONFIG.DEBUG_MODE then
            print("[AI DEBUG] ОШИБКА ПАРСИНГА: " .. tostring(tbl))
        end
        return
    end
    if not tbl or type(tbl) ~= "table" then
        if AI_CONFIG and AI_CONFIG.DEBUG_MODE then
            print("[AI DEBUG] ОШИБКА: результат не таблица, а " .. type(tbl))
        end
        return
    end
    if AI_CONFIG and AI_CONFIG.DEBUG_MODE then
        print("[AI DEBUG] Успешно распарсено, ключей: " .. table.Count(tbl))
    end
    AI_SETTINGS = tbl
    ApplyClientSettings(tbl)
    if IsValid(_G.AICompanionMenuPanel) then
        pcall(function()
            if _G.AICompanionMenuPanel.RefreshValues then
                _G.AICompanionMenuPanel:RefreshValues()
            end
        end)
    end
end)
function ApplyClientSettings(settings)
    if not settings then return end
    AI_SETTINGS = settings
    if AC then
        if not AC.Settings then
            AC.Settings = settings
        else
            for k, v in pairs(settings) do
                AC.Settings[k] = v
            end
        end
    end
    _G.AI_Companion_PrefixText = settings.prefix_text or "[AI]"
    _G.AI_Companion_PrefixRainbow = settings.prefix_rainbow or false
    _G.AI_Companion_PrefixColorR = settings.prefix_r or 255
    _G.AI_Companion_PrefixColorG = settings.prefix_g or 200
    _G.AI_Companion_PrefixColorB = settings.prefix_b or 0
    if _G.AI_COMPANION_DEF and _G.AI_COMPANION_DEF.Appearance and _G.AI_COMPANION_DEF.Appearance.Prefix then
        _G.AI_COMPANION_DEF.Appearance.Prefix.Text = settings.prefix_text or "[AI]"
        _G.AI_COMPANION_DEF.Appearance.Prefix.Rainbow = settings.prefix_rainbow or false
        if _G.AI_COMPANION_DEF.Appearance.Prefix.Color then
            _G.AI_COMPANION_DEF.Appearance.Prefix.Color.R = settings.prefix_r or 255
            _G.AI_COMPANION_DEF.Appearance.Prefix.Color.G = settings.prefix_g or 200
            _G.AI_COMPANION_DEF.Appearance.Prefix.Color.B = settings.prefix_b or 0
        end
    end
    local ply = LocalPlayer()
    if IsValid(ply) and AI_Utils and AI_Utils.InvalidatePrefixCache then
        AI_Utils.InvalidatePrefixCache(ply)
    end
    if IsValid(_G.AICompanionMenuPanel) then
        pcall(function()
            if _G.AICompanionMenuPanel.RefreshValues then
                _G.AICompanionMenuPanel:RefreshValues()
            end
        end)
    end
end
local settingsRequestCooldowns = {}
hook.Add("PlayerInitialSpawn", "AICompanion_RequestSettings", function()
    if game.SinglePlayer() then
        timer.Simple(1, function()
            if AI_LoadSettings then
                AI_LoadSettings()
            end
            if AI_ApplySettings then
                AI_ApplySettings()
            end
            if AC and AC.Settings and AI_SETTINGS then
                for k, v in pairs(AI_SETTINGS) do
                    AC.Settings[k] = v
                end
            end
            if IsValid(_G.AICompanionMenuPanel) then
                pcall(function()
                    if _G.AICompanionMenuPanel.RefreshValues then
                        _G.AICompanionMenuPanel:RefreshValues()
                    end
                end)
            end
            if AI_DebugPrint then
                AI_DebugPrint("[AI Client] Соло-режим: настройки загружены локально")
            end
        end)
        return
    end
    timer.Simple(2, function()
        local ply = LocalPlayer()
        if IsValid(ply) then
            local steamID = ply:SteamID64()
            local lastRequest = settingsRequestCooldowns[steamID] or 0
            if CurTime() - lastRequest > 10 then
                settingsRequestCooldowns[steamID] = CurTime()
                RunConsoleCommand("ai_request_settings")
            end
        end
    end)
end)
if AI_DebugPrint then
    AI_DebugPrint("[AI Client] Загружен")
end