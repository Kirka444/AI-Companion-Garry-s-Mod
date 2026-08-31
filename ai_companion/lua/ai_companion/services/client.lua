local Client = {}

function Client:new(utils, config, state, shared)
    local obj = {
        utils = utils,
        config = config,
        state = state,
        shared = shared,
        _initialized = false,
        _avatarMat = nil,
        _avatarPreloaded = false,
        _customAvatarPath = nil,
        _avatarDataPath = "data/avatar.png",
        _avatarSavePath = "ai_companion/avatar.png",
        _avatarConfigFile = "ai_companion/avatar_config.txt",
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function Client:init()
    if self._initialized then return end

    if CLIENT then
        self:SetupScoreboard()
        self:SetupNetReceivers()
        self:SetupCommands()
        self:SetupChatHooks()

        print("[AI Client] Клиентский сервис инициализирован")
    end

    self._initialized = true
    if self.utils then
        self.utils.LogInfo("Client", "Клиентский сервис инициализирован")
    end
end

function Client:IsValid(ent)
    return self.utils and self.utils:IsValid(ent)
end

function Client:GetSetting(key, default)
    if self.state then
        local val = self.state:getSetting(key)
        if val ~= nil then return val end
    end
    return default
end

function Client:GetState(key, default)
    if self.state then
        local val = self.state:getState(key)
        if val ~= nil then return val end
    end
    return default
end

function Client:GetMySetting(key, default)
    local ply = LocalPlayer()
    if not self:IsValid(ply) then return default end
    if not self.state then return default end
    
    
    local val = self.state:getPlayerSetting(ply:SteamID64(), key, default)
    
    
    if val == nil then
        val = self.state:getPlayerSetting(ply:SteamID64(), string.lower(key), default)
    end
    
    return val
end

function Client:LoadAvatarConfig()
    if not file.Exists(self._avatarConfigFile, "DATA") then return end

    local content = file.Read(self._avatarConfigFile, "DATA")
    if not content or content == "" then return end

    
    if file.Exists(content, "GAME") or file.Exists(content, "DATA") then
        self._customAvatarPath = content
        if self.utils then
            self.utils.LogInfo("Client", "Загружена кастомная аватарка: %s", content)
        end
    else
        self._customAvatarPath = nil
        if self.utils then
            self.utils.LogWarn("Client", "Сохранённая аватарка не найдена: %s", content)
        end
    end
end

function Client:SaveAvatarConfig(path)
    if not path then
        if file.Exists(self._avatarConfigFile, "DATA") then
            file.Delete(self._avatarConfigFile)
        end
        return
    end
    file.Write(self._avatarConfigFile, path)
end

function Client:CopyAvatarToMaterials()
    
    if not file.Exists(self._avatarDataPath, "DATA") then
        return false, "Файл не найден: " .. self._avatarDataPath
    end

    
    if not file.Exists("ai_companion", "DATA") then
        file.CreateDir("ai_companion")
    end

    
    local data = file.Read(self._avatarDataPath, "DATA")
    if not data or #data == 0 then
        return false, "Файл пустой или не читается"
    end

    
    local isPNG = string.sub(data, 1, 8) == string.char(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
    local isJPG = string.sub(data, 1, 3) == string.char(0xFF, 0xD8, 0xFF)

    if not isPNG and not isJPG then
        return false, "Файл не является PNG или JPEG изображением"
    end

    
    local targetPath = "ai_companion/avatar.png"
    file.Write(targetPath, data)

    if not file.Exists(targetPath, "DATA") then
        return false, "Не удалось записать файл в materials/"
    end

    
    self._avatarMat = nil
    self._avatarPreloaded = false

    return true, "Файл скопирован в materials/ai_companion/avatar.png (" .. #data .. " байт)"
end

function Client:GetAvatarMat()
    if self._avatarMat and not self._avatarMat:IsError() then
        return self._avatarMat
    end

    local paths = {}

    
    if self._customAvatarPath then
        table.insert(paths, self._customAvatarPath)
    end

    
    table.insert(paths, "ai_companion/avatar.png")
    table.insert(paths, "ai_companion/avatar.jpg")
    table.insert(paths, "icon16/user.png")

    for _, path in ipairs(paths) do
        local mat = Material(path, "smooth mips")
        if mat and not mat:IsError() then
            self._avatarMat = mat
            return mat
        end
    end

    local dummyMat = Material("color", "smooth")
    self._avatarMat = dummyMat
    return dummyMat
end

function Client:PreloadAvatar()
    if self._avatarPreloaded then return end

    timer.Simple(0.5, function()
        if not self._avatarMat then
            self:GetAvatarMat()
            self._avatarPreloaded = true
        end
    end)
end

function Client:ApplyAvatarOverride(entry)
    if not self:IsValid(entry) then return false end
    if not self:IsValid(entry.Player) then return false end
    if not entry.Player:GetNWBool("IsAICompanion", false) then return false end

    local mat = self:GetAvatarMat()
    if not mat or mat:IsError() then return false end

    if not IsValid(entry.Avatar) then
        return false
    end

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

function Client:SetupScoreboard()
    if not CLIENT then return end

    hook.Add("ScoreboardPlayerRowCreated", "AICompanion_AvatarOnRowCreate", function(panel, ply)
        if not self:IsValid(ply) then return end
        if not self:IsValid(panel) then return end

        if ply:GetNWBool("IsAICompanion", false) then
            timer.Simple(0.1, function()
                if self:IsValid(panel) and self:IsValid(panel.Player) and panel.Player == ply then
                    self:ApplyAvatarOverride(panel)
                end
            end)
        end
    end)

    hook.Add("ScoreboardShow", "AICompanion_AvatarFallback", function()
        timer.Simple(0.1, function()
            for _, pl in ipairs(player.GetAll()) do
                if self:IsValid(pl.ScoreEntry) then
                    self:ApplyAvatarOverride(pl.ScoreEntry)
                end
            end
        end)
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
end

function Client:GetPrefixColor(ply)
    if not self:IsValid(ply) then return Color(255, 200, 0) end

    local steamID = ply:SteamID64()

    local rainbow = false
    local r, g, b = 255, 200, 0

    if self.state then
        rainbow = self.state:getPlayerSetting(steamID, "Prefix_Rainbow", false)
        r = self.state:getPlayerSetting(steamID, "Prefix_Color_R", 255)
        g = self.state:getPlayerSetting(steamID, "Prefix_Color_G", 200)
        b = self.state:getPlayerSetting(steamID, "Prefix_Color_B", 0)
    end

    if rainbow then
        local hue = (CurTime() * 120) % 360
        return HSVToColor(hue, 1, 1)
    end

    return Color(r, g, b)
end

function Client:GetCleanPrefix(ply)
    if not self:IsValid(ply) then return "AI" end

    local steamID = ply:SteamID64()
    local prefix = "[AI]"

    if self.state then
        prefix = self.state:getPlayerSetting(steamID, "Prefix_Text", "[AI]")
    end

    local clean = string.gsub(prefix, "^%[", "")
    clean = string.gsub(clean, "%]$", "")
    clean = string.Trim(clean)
    if clean == "" then clean = "AI" end
    return clean
end

function Client:SetupNetReceivers()
    if not CLIENT then return end

	net.Receive("AI_Companion_Chat", function()
		local text = net.ReadString()
		local color = net.ReadColor()
		local sender = net.ReadString() or "AI"
		local receiver = net.ReadString() or ""

		if not text or text == "" then return end

		local cleanPrefix = self:GetMySetting("Prefix_Text", "[AI]")
		local prefixColor = Color(
			self:GetMySetting("Prefix_Color_R", 255),
			self:GetMySetting("Prefix_Color_G", 200),
			self:GetMySetting("Prefix_Color_B", 0)
		)

		if self:GetMySetting("Prefix_Rainbow", false) then
			local hue = (CurTime() * 120) % 360
			prefixColor = HSVToColor(hue, 1, 1)
		end

		local prefixText = string.gsub(cleanPrefix, "^%[", "")
		prefixText = string.gsub(prefixText, "%]$", "")

		if receiver and receiver ~= "" then

			chat.AddText(prefixColor, "[" .. prefixText .. " -> " .. receiver .. "] ", Color(255, 255, 255), text)
		else

			chat.AddText(prefixColor, cleanPrefix .. " ", Color(255, 255, 255), text)
		end
	end)

	net.Receive("AI_Companion_Private_Chat", function()
		local text = net.ReadString()
		local color = net.ReadColor()
		local sender = net.ReadString() or "AI"
		local receiver = net.ReadString() or ""

		if not text or text == "" then return end

		local cleanPrefix = self:GetMySetting("Prefix_Text", "[AI]")
		local prefixColor = Color(
			self:GetMySetting("Prefix_Color_R", 255),
			self:GetMySetting("Prefix_Color_G", 200),
			self:GetMySetting("Prefix_Color_B", 0)
		)

		if self:GetMySetting("Prefix_Rainbow", false) then
			local hue = (CurTime() * 120) % 360
			prefixColor = HSVToColor(hue, 1, 1)
		end

		local prefixText = string.gsub(cleanPrefix, "^%[", "")
		prefixText = string.gsub(prefixText, "%]$", "")

		if receiver and receiver ~= "" then
			chat.AddText(prefixColor, "Приват: [" .. prefixText .. " -> " .. receiver .. "] ", Color(255, 255, 255), text)
		else
			chat.AddText(prefixColor, "Приват: " .. cleanPrefix .. " ", Color(255, 255, 255), text)
		end
	end)

    net.Receive("AI_Companion_PlayAudio", function()
        local url = net.ReadString()
        if not url or url == "" then
            if self.utils then
                self.utils.LogDebug("Client", "Пустой URL для TTS")
            end
            return
        end

        self:PlayAudio(url)
    end)
end

function Client:PlayAudio(url)
    if not url or url == "" then return end

    if self.utils then
        self.utils.LogDebug("Client", "TTS URL: %s", url)
    end

    if not file.Exists("ai_companion_cache", "DATA") then
        file.CreateDir("ai_companion_cache")
    end

    local fileName = "ai_tts_" .. os.time() .. "_" .. math.random(1000, 9999) .. ".mp3"
    local cachePath = "ai_companion_cache/" .. fileName

    http.Fetch(url,
        function(body, size, headers, code)
            if code ~= 200 or not body or #body < 100 then
                if self.utils then
                    self.utils.LogWarn("Client", "Ошибка загрузки TTS: код %d, размер %d", code, size)
                end
                chat.AddText(Color(255,100,100), "[AI] Ошибка загрузки голоса")
                return
            end

            if self.utils then
                self.utils.LogDebug("Client", "TTS скачан: %d байт", #body)
            end

            file.Write(cachePath, body)
            local fullPath = "data/" .. cachePath

            sound.PlayFile(fullPath, "mono", function(station, err)
                if IsValid(station) and not err then
                    station:SetVolume(1.0)
                    station:Play()
                    if self.utils then
                        self.utils.LogDebug("Client", "TTS воспроизводится")
                    end

                    local lifetime = 30
                    if self.config and self.config:get("TTS") then
                        lifetime = self.config:get("TTS").AudioCacheLifetime or 30
                    end

                    timer.Simple(lifetime, function()
                        if file.Exists(cachePath, "DATA") then
                            file.Delete(cachePath)
                        end
                    end)
                else
                    if self.utils then
                        self.utils.LogWarn("Client", "Ошибка воспроизведения TTS: %s", tostring(err))
                    end
                    chat.AddText(Color(255,100,100), "[AI] Ошибка воспроизведения: " .. tostring(err))
                end
            end)
        end,
        function(err)
            if self.utils then
                self.utils.LogError("Client", "Ошибка http.Fetch для TTS: %s", tostring(err))
            end
            chat.AddText(Color(255,100,100), "[AI] Не удалось скачать голос")
        end
    )
end

function Client:SetupCommands()
    if not CLIENT then return end

    
    self:LoadAvatarConfig()

    concommand.Add("ai_request_settings", function()
        net.Start("AI_Settings_Request")
        net.SendToServer()
        chat.AddText(Color(100, 200, 255), "[AI] Запрос настроек отправлен")
    end)

	concommand.Add("ai_request_player_settings", function()
		if not self._lastRequest then self._lastRequest = 0 end
		if CurTime() - self._lastRequest < 2 then
			chat.AddText(Color(255, 200, 100), "[AI] Подождите немного перед повторным запросом")
			return
		end
		self._lastRequest = CurTime()

		net.Start("AI_RequestPlayerSettings")
		net.SendToServer()
		chat.AddText(Color(100, 200, 255), "[AI] Запрос персональных настроек отправлен")
	end)

    concommand.Add("ai_request_config", function()
        net.Start("AICompanion_RequestConfig")
        net.SendToServer()
        chat.AddText(Color(100, 200, 255), "[AI] Запрос конфига отправлен")
    end)

    concommand.Add("ai_avatar_check", function()
        local mat = self:GetAvatarMat()
        if mat and not mat:IsError() then
            local name = (mat.GetName and mat:GetName()) or "unknown"
            chat.AddText(Color(0, 255, 0), "[AI] Аватарка загружена: " .. name)
        else
            chat.AddText(Color(255, 0, 0), "[AI] Аватарка не найдена!")
        end
    end)

    concommand.Add("ai_avatar_force", function()
        local mat = self:GetAvatarMat()
        if not mat or mat:IsError() then
            chat.AddText(Color(255, 0, 0), "[AI] Материал не загружен")
            return
        end

        local count = 0
        for _, pl in ipairs(player.GetAll()) do
            if self:ApplyAvatarOverride(pl.ScoreEntry) then
                count = count + 1
            end
        end
        chat.AddText(Color(0, 255, 0), "[AI] Аватарка установлена для " .. count .. " ботов")
    end)

    
    concommand.Add("ai_companion_avatar", function(ply, cmd, args)
        local subcmd = args[1] or "set"

        if subcmd == "set" then
            
            if not file.Exists(self._avatarDataPath, "DATA") then
                chat.AddText(Color(255, 100, 100), "[AI] Файл не найден: " .. self._avatarDataPath)
                chat.AddText(Color(200, 200, 200), "[AI] Поместите изображение по пути: garrysmod/" .. self._avatarDataPath)
                chat.AddText(Color(200, 200, 200), "[AI] Поддерживаемые форматы: PNG, JPG")
                return
            end

            
            local ok, msg = self:CopyAvatarToMaterials()
            if not ok then
                chat.AddText(Color(255, 100, 100), "[AI] Ошибка: " .. msg)
                return
            end

            
            self._customAvatarPath = self._avatarSavePath
            self:SaveAvatarConfig(self._avatarSavePath)

            
            self._avatarMat = nil
            self._avatarPreloaded = false
            self:GetAvatarMat()

            
            local count = 0
            for _, pl in ipairs(player.GetAll()) do
                if self:ApplyAvatarOverride(pl.ScoreEntry) then
                    count = count + 1
                end
            end

            chat.AddText(Color(0, 255, 0), "[AI] ✅ Аватарка установлена из data/avatar.png")
            chat.AddText(Color(100, 255, 100), "[AI] " .. msg)
            chat.AddText(Color(100, 255, 100), "[AI] Обновлено записей: " .. count)

        elseif subcmd == "reset" or subcmd == "default" then
            self._customAvatarPath = nil
            self._avatarMat = nil
            self._avatarPreloaded = false
            self:SaveAvatarConfig(nil)

            
            if file.Exists(self._avatarSavePath, "DATA") then
                file.Delete(self._avatarSavePath)
            end

            self:GetAvatarMat()

            local count = 0
            for _, pl in ipairs(player.GetAll()) do
                if self:ApplyAvatarOverride(pl.ScoreEntry) then
                    count = count + 1
                end
            end

            chat.AddText(Color(0, 255, 0), "[AI] ✅ Аватарка сброшена на стандартную")
            chat.AddText(Color(100, 255, 100), "[AI] Обновлено записей: " .. count)

        elseif subcmd == "path" and args[2] then
            
            local customPath = args[2]
            self._customAvatarPath = customPath
            self:SaveAvatarConfig(customPath)
            self._avatarMat = nil
            self._avatarPreloaded = false
            self:GetAvatarMat()

            local count = 0
            for _, pl in ipairs(player.GetAll()) do
                if self:ApplyAvatarOverride(pl.ScoreEntry) then
                    count = count + 1
                end
            end

            chat.AddText(Color(0, 255, 0), "[AI] ✅ Аватарка изменена на: " .. customPath)
            chat.AddText(Color(100, 255, 100), "[AI] Обновлено записей: " .. count)

        else
            chat.AddText(Color(255, 200, 100), "[AI] === Управление аватаркой ===")
            chat.AddText(Color(200, 200, 200), "Использование:")
            chat.AddText(Color(200, 200, 200), "  ai_companion_avatar set          — установить из data/avatar.png")
            chat.AddText(Color(200, 200, 200), "  ai_companion_avatar reset        — сбросить на стандартную")
            chat.AddText(Color(200, 200, 200), "  ai_companion_avatar path <путь>  — установить произвольный путь")
        end
    end)

    concommand.Add("ai_companion_avatar_info", function()
        chat.AddText(Color(100, 200, 255), "[AI] === Информация об аватарке ===")

        local mat = self:GetAvatarMat()
        if mat and not mat:IsError() then
            local name = (mat.GetName and mat:GetName()) or "unknown"
            chat.AddText(Color(0, 255, 0), "  Активный материал: " .. name)
        else
            chat.AddText(Color(255, 100, 100), "  Активный материал: ОШИБКА")
        end

        if self._customAvatarPath then
            chat.AddText(Color(0, 255, 0), "  Кастомный путь: " .. self._customAvatarPath)
        else
            chat.AddText(Color(200, 200, 200), "  Кастомный путь: не установлен")
        end

        chat.AddText(Color(200, 200, 200), "  Источник (data): " .. self._avatarDataPath)
        if file.Exists(self._avatarDataPath, "DATA") then
            local size = file.Size(self._avatarDataPath, "DATA")
            chat.AddText(Color(0, 255, 0), "    Файл найден (" .. size .. " байт)")
        else
            chat.AddText(Color(255, 100, 100), "    Файл отсутствует")
        end

        chat.AddText(Color(200, 200, 200), "  Копия (materials): " .. self._avatarSavePath)
        if file.Exists(self._avatarSavePath, "DATA") then
            local size = file.Size(self._avatarSavePath, "DATA")
            chat.AddText(Color(0, 255, 0), "    Файл найден (" .. size .. " байт)")
        else
            chat.AddText(Color(255, 100, 100), "    Файл отсутствует")
        end

        if file.Exists(self._avatarConfigFile, "DATA") then
            chat.AddText(Color(0, 255, 0), "  Конфиг сохранён")
        else
            chat.AddText(Color(200, 200, 200), "  Конфиг: не сохранён")
        end
    end)

    concommand.Add("ai_companion_menu", function()
        local locator = _G.AI_GetLocator()
        if locator and locator:has("menu") then
            local menu = locator:get("menu")
            menu:Open()
        end
    end)

    concommand.Add("ai_client_debug", function()
        local locator = _G.AI_GetLocator()
        if locator and locator:has("client") then
            local client = locator:get("client")
            client:DebugPrint()
        else
            print("[AI] Client не найден!")
        end
    end)
end

function Client:SetupChatHooks()
    if not CLIENT then return end

    hook.Add("ChatText", "AICompanion_ChatFilter", function(index, name, text, typ)

        if typ == "chat" and name and string.find(name, "%[AI") then

        end
    end)
end

function Client:DebugPrint()
    print("")
    print("═══════════════════════════════════════════════════════")
    print("        AI COMPANION - КЛИЕНТ")
    print("═══════════════════════════════════════════════════════")
    print("")
    print("  Avatar loaded: " .. tostring(self._avatarMat and not self._avatarMat:IsError()))

    local ply = LocalPlayer()
    if self:IsValid(ply) then
        print("  Prefix: " .. self:GetCleanPrefix(ply))
        print("  Prefix Color: " .. tostring(self:GetPrefixColor(ply)))
    end

    local ttsEnabled = false
    local llmEnabled = true
    if self.state then
        ttsEnabled = self.state:getState("TTS_Enabled") or false
        llmEnabled = self.state:getState("LLM_Enabled") or true
    end
    print("  TTS Enabled: " .. tostring(ttsEnabled))
    print("  LLM Enabled: " .. tostring(llmEnabled))
    print("")
    print("═══════════════════════════════════════════════════════")
    print("")
end

return Client