
local Menu = {}

local GLOBAL_KEYS = {

    LLM_IP = true, LLM_Port = true, LLM_Model = true,
    LLM_Mode = true, LLM_Provider = true, LLM_API_Key = true,
    LLM_Cloud_Model = true, LLM_Endpoint = true,
    LLM_Temperature = true, LLM_Max_Tokens = true, LLM_Timeout = true,

    TTS_IP = true, TTS_Port = true, TTS_Mode = true,
    TTS_Provider = true, TTS_API_Key = true,
    TTS_Voice = true, TTS_Language = true, TTS_Endpoint = true,
    TTS_Timeout = true, TTS_Speed = true,

    Yandex_Folder_ID = true, Yandex_Voice = true, Yandex_Lang = true,

    VK_Voice = true, VK_Tempo = true,

    Debug_Mode = true, Auto_Sync_Global = true,
    Allow_Custom_Prompts = true, Locale = true,
    TTS_Enabled = true, LLM_Enabled = true,
}

function Menu:new(utils, config, state, client, shared, botmanager, locale)
    local obj = {
        utils = utils,
        config = config,
        state = state,
        client = client,
        shared = shared,
        botmanager = botmanager,
        locale = locale,
        _initialized = false,
        _panel = nil,
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function Menu:IsGlobalKey(key)
    return GLOBAL_KEYS[key] == true
end

function Menu:L(key, ...)
    if self.locale then
        return self.locale:Get(key, ...)
    end
    return key
end

function Menu:init()
    if self._initialized then return end
    if not CLIENT then return end

    if not self.locale then
        self.locale = _G.AI_GetLocale and _G.AI_GetLocale() or {
            Get = function(_, key) return key end,
            GetLang = function() return "en" end,
            SetLang = function(_, lang) end,
            GetAvailable = function() return {"en"} end,
        }
    end

    self:RegisterPanel()
    self:SetupNetReceivers()

    timer.Simple(0.1, function()
        if CLIENT then
            hook.Run("PopulateToolMenu")
        end
    end)

    self._initialized = true
    if self.utils then
        self.utils.LogInfo("Menu", "Меню инициализировано")
    end
end
function Menu:RefreshValues()
    if self:IsValid(_G.AICompanionMenuPanel) then
        _G.AICompanionMenuPanel:RefreshValues()
    end
end

function Menu:IsValid(ent)

    if self.utils and self.utils.IsValid then
        return self.utils:IsValid(ent)
    end
    return IsValid(ent)
end

function Menu:GetSetting(key, default)
    if self.state then
        local val = self.state:getSetting(key)
        if val ~= nil then return val end
    end
    return default
end

function Menu:GetState(key, default)
    if self.state then
        local val = self.state:getState(key)
        if val ~= nil then return val end
    end
    return default
end

function Menu:GetAllSettings()
    local now = CurTime()
    if self._settingsCache and self._settingsCacheTime and (now - self._settingsCacheTime) < 0.5 then
        return self._settingsCache
    end
    
    local settings = {}
    if self.state then
        
        local raw = self.state:getRaw("Settings") or {}
        for k, v in pairs(raw) do
            settings[k] = v
        end
        local ttsEnabled = self.state:getState("TTS_Enabled")
        if ttsEnabled ~= nil then settings.tts_enabled = ttsEnabled else settings.tts_enabled = false end
        local llmEnabled = self.state:getState("LLM_Enabled")
        if llmEnabled ~= nil then settings.llm_enabled = llmEnabled else settings.llm_enabled = true end

        -- Алиасы для статус-панели, которая читает lowercase-ключи
        settings.llm_mode = settings.LLM_Mode or settings.llm_mode or "local"
        settings.tts_mode = settings.TTS_Mode or settings.tts_mode or "local"
        settings.llm_timeout = settings.LLM_Timeout or settings.llm_timeout or 60
        settings.tts_timeout = settings.TTS_Timeout or settings.tts_timeout or 120
        
        
        local ply = LocalPlayer()
        if self:IsValid(ply) then
            local steamID = ply:SteamID64()
            
            settings.Prefix_Text       = self.state:getPlayerSetting(steamID, "Prefix_Text", "[AI]")
            settings.Prefix_Color_R    = self.state:getPlayerSetting(steamID, "Prefix_Color_R", 255)
            settings.Prefix_Color_G    = self.state:getPlayerSetting(steamID, "Prefix_Color_G", 200)
            settings.Prefix_Color_B    = self.state:getPlayerSetting(steamID, "Prefix_Color_B", 0)
            settings.Prefix_Rainbow    = self.state:getPlayerSetting(steamID, "Prefix_Rainbow", false)
            settings.Show_Sender_Name  = self.state:getPlayerSetting(steamID, "Show_Sender_Name", true)
            
            settings.Companion_Nick    = self.state:getPlayerSetting(steamID, "Companion_Nick", "AI_Companion")
            settings.Model_Path        = self.state:getPlayerSetting(steamID, "Model_Path", "models/player/urban.mdl")
            settings.Combat_Weapon     = self.state:getPlayerSetting(steamID, "Combat_Weapon", "weapon_smg1")
            settings.Melee_Weapon      = self.state:getPlayerSetting(steamID, "Melee_Weapon", "weapon_crowbar")
            settings.Idle_Weapon       = self.state:getPlayerSetting(steamID, "Idle_Weapon", "weapon_physgun")
            
            settings.Stealth_Mode      = self.state:getPlayerSetting(steamID, "Stealth_Mode", false)
            settings.Defender_Mode     = self.state:getPlayerSetting(steamID, "Defender_Mode", false)
            settings.Medic_Mode        = self.state:getPlayerSetting(steamID, "Medic_Mode", false)
            settings.Pacifist_Mode     = self.state:getPlayerSetting(steamID, "Pacifist_Mode", false)
            settings.Aggressive_Mode   = self.state:getPlayerSetting(steamID, "Aggressive_Mode", false)
            
            settings.Custom_Prompt_Enabled = self.state:getPlayerSetting(steamID, "Custom_Prompt_Enabled", false)
            settings.Custom_Prompt_Text    = self.state:getPlayerSetting(steamID, "Custom_Prompt_Text", "")
        end
    end
    
    self._settingsCache = settings
    self._settingsCacheTime = now
    return settings
end

function Menu:SendSettingToServer(key, value)
    if not CLIENT then return end

    self.utils.LogDebug("[Menu] SendSettingToServer: " .. key .. " = " .. tostring(value))

    self._settingsCache = nil
    self._settingsCacheTime = nil

    if self.state then

		local personalKeys = {
			["Show_Sender_Name"] = true,
			["Companion_Nick"] = true,
			["Model_Path"] = true,
			["Combat_Weapon"] = true,
			["Melee_Weapon"] = true,
			["Idle_Weapon"] = true,
			["Stealth_Mode"] = true,
			["Defender_Mode"] = true,
			["Medic_Mode"] = true,
			["Pacifist_Mode"] = true,
			["Aggressive_Mode"] = true,
			["Prefix_Text"] = true,
			["Prefix_Rainbow"] = true,
			["Prefix_Color_R"] = true,
			["Prefix_Color_G"] = true,
			["Prefix_Color_B"] = true,
			["Custom_Prompt_Enabled"] = true,
			["Custom_Prompt_Text"] = true,
		}

        local isPersonal = personalKeys[key] or personalKeys[string.lower(key)]

        if isPersonal then
            local steamID = LocalPlayer():SteamID64()
            self.utils.LogDebug("[Menu] 📤 Отправка на сервер: " .. key .. " = " .. tostring(value) .. " (PERSONAL)")
            self.state:setPlayerSetting(steamID, key, value)

            net.Start("AICompanion_SetSetting")
            net.WriteString(key)
            net.WriteString(tostring(value))
            net.SendToServer()
        else
            self.utils.LogDebug("[Menu] 📤 Отправка на сервер: " .. key .. " = " .. tostring(value) .. " (GLOBAL)")
            self.state:setState(key, value)
        end
    end
end

function Menu:GetCompanion(ply)
    if not self:IsValid(ply) then return nil end

    if self.botmanager then
        local bot = self.botmanager:GetBotByOwner(ply)
        if self:IsValid(bot) then
            return bot
        end
    end

    for _, bot in ipairs(player.GetAll()) do
        if self:IsValid(bot) and bot:IsPlayer() and bot:GetNWBool("IsAICompanion", false) then
            local owner = bot:GetNWEntity("AICompanionOwnerEnt")
            if self:IsValid(owner) and owner == ply then
                return bot
            end

            local ownerName = bot:GetNWString("AICompanionOwner", "")
            if ownerName ~= "" and ownerName == ply:Nick() then
                return bot
            end
        end
    end
    return nil
end

function Menu:HasCompanion(ply)
    if not self:IsValid(ply) then return false end
    local bot = self:GetCompanion(ply)
    local result = self:IsValid(bot)

    if CLIENT then
        self.utils.LogDebug("[Menu DEBUG] HasCompanion для", ply:Nick(), "bot=", bot, "result=", result)
        if not result then
            self.utils.LogDebug("[Menu DEBUG] Все игроки:")
            for _, p in ipairs(player.GetAll()) do
                if IsValid(p) then
                    self.utils.LogDebug("  ", p:Nick(), "IsAICompanion=", p:GetNWBool("IsAICompanion", false), "IsBot=", p:IsBot())
                end
            end
        end
    end
    return result
end

function Menu:GetBotState(bot)
    if not self:IsValid(bot) then return "idle" end

    if self.botmanager then
        local state = self.botmanager:GetBotState(bot)
        if state then return state end
    end
    return bot:GetNWString("BotState", "idle")
end

function Menu:GetAllCompanions()
    local bots = {}

    if self.botmanager then
        local bmBots = self.botmanager:GetAllBots()
        if bmBots and #bmBots > 0 then
            return bmBots
        end
    end

    for _, bot in ipairs(player.GetAll()) do
        if self:IsValid(bot) and bot:IsPlayer() and bot:GetNWBool("IsAICompanion", false) then
            table.insert(bots, bot)
        end
    end
    return bots
end

function Menu:RegisterPanel()
    if not CLIENT then return end

    local selfRef = self

    local PANEL = {}
    PANEL.InputFields = {}
    PANEL.ToggleChecks = {}
    PANEL.LangCombo = nil
    PANEL.UpdateLanguageCombo = nil

	function PANEL:RunCommand(cmd)
		local ply = LocalPlayer()
		if selfRef:IsValid(ply) then

			RunConsoleCommand(cmd)

			chat.AddText(Color(100, 200, 255), "[AI] Выполнена команда: " .. cmd)
		end
	end

	function PANEL:Init()
		self:SetTitle(selfRef:L("menu_title"))
		self:SetSize(800, 600)
		self:Center()
		self:MakePopup()

		self._isUpdating = false

		if not self._settingsLoaded then
			if CLIENT then
				RunConsoleCommand("ai_request_settings")
				RunConsoleCommand("ai_request_player_settings")
			end
			self._settingsLoaded = true
		end

		self.Sheet = vgui.Create("DPropertySheet", self)
		self.Sheet:Dock(FILL)
		self.Sheet:DockMargin(5, 5, 5, 5)

		self:BuildMainTab()
		self:BuildLLMTab()
		self:BuildTTSTab()

		if not game.SinglePlayer() then
			self:BuildBotTab()
			self:BuildCombatTab()
		end

		self:BuildAppearanceTab()
		self:BuildInfoTab()
		self:BuildPromptTab()
		self:BuildWorkflowTab()
		self:BuildMemoryTab()

		timer.Simple(0.3, function()
			if selfRef:IsValid(self) then
				self:RefreshValues()
			end
		end)
	end

	function PANEL:RefreshAllTabs()

		if self._isUpdating then
			return
		end
		self._isUpdating = true

		local savedValues = {}
		for key, entry in pairs(self.InputFields) do
			if selfRef:IsValid(entry) then
				savedValues[key] = entry:GetText()
			end
		end

		if selfRef:IsValid(self.Sheet) then
			self.Sheet:Clear()
		end

		self:BuildMainTab()
		self:BuildLLMTab()
		self:BuildTTSTab()

		if not game.SinglePlayer() then
			self:BuildBotTab()
			self:BuildCombatTab()
		end

		self:BuildAppearanceTab()
		self:BuildInfoTab()
		self:BuildPromptTab()
		self:BuildWorkflowTab()
		self:BuildMemoryTab() 
		self:RefreshValues()

		timer.Simple(0.15, function()
			if not selfRef:IsValid(self) then
				self._isUpdating = false
				return
			end
			for key, value in pairs(savedValues) do
				local entry = self.InputFields[key]
				if selfRef:IsValid(entry) then
					entry._updatingFromServer = true
					entry:SetText(value)
					entry._lastText = value
					timer.Simple(0.1, function()
						if selfRef:IsValid(entry) then
							entry._updatingFromServer = false
						end
					end)
				end
			end
			self._isUpdating = false
		end)

		if self.UpdateLanguageCombo then
			self:UpdateLanguageCombo()
		end
	end

	function PANEL:RefreshValues()

		if self._isUpdating then
			return
		end
		self._isUpdating = true

		local ply = LocalPlayer()
		if not selfRef:IsValid(ply) then
			self._isUpdating = false
			return
		end

		local steamID = ply:SteamID64()
		local settings = selfRef:GetAllSettings()
		local isAdmin = ply:GetNWBool("AI_IsAdmin", false)

		for key, entry in pairs(self.InputFields) do
			if selfRef:IsValid(entry) then
				if not entry:IsEditing() then
					local isGlobal = selfRef:IsGlobalKey(key)

					if isGlobal and not isAdmin then
						entry:SetEditable(false)
						entry:SetTooltip("Глобальная настройка (только для администратора)")
					elseif isGlobal and isAdmin then
						entry:SetEditable(true)
						entry:SetTooltip("Глобальная настройка (изменяется для всех игроков)")
					else
						entry:SetEditable(true)
						entry:SetTooltip("")
					end

					local val
					if isGlobal then
						val = settings[key]
					else

						val = settings[key]
						if val == nil then
							val = selfRef.state:getPlayerSetting(steamID, key, nil)
						end
					end

					if val ~= nil then
						local strVal = tostring(val)
						if entry:GetText() ~= strVal then
							entry._updatingFromServer = true
							entry._lastText = strVal
							entry:SetText(strVal)
							timer.Simple(0.5, function()
								if selfRef:IsValid(entry) then
									entry._updatingFromServer = false
								end
							end)
						end
					end
				end
			end
		end

		for key, btn in pairs(self.ToggleChecks) do
			if selfRef:IsValid(btn) then
				local isGlobal = selfRef:IsGlobalKey(key)
				if isGlobal and not isAdmin then
					btn:SetEnabled(false)
					btn:SetTooltip("Глобальная настройка (только для администратора)")
				elseif isGlobal and isAdmin then
					btn:SetEnabled(true)
					btn:SetTooltip("Глобальная настройка (изменяется для всех игроков)")
				else
					btn:SetEnabled(true)
					btn:SetTooltip("")
				end

				local val = settings[key]

				if type(val) == "string" then
					if val == "true" then val = true
					elseif val == "false" then val = false
					end
				end

				if val ~= nil and btn._state ~= val then
					btn._state = val
					btn:UpdateColors()
					btn:InvalidateLayout()
				end
			end
		end

		local senderToggle = self.ToggleChecks["Show_Sender_Name"]
		if selfRef:IsValid(senderToggle) then
			local val = settings.Show_Sender_Name
			if val == nil then
				val = selfRef.state:getPlayerSetting(steamID, "Show_Sender_Name", true)
			end

			if type(val) == "string" then
				if val == "true" then val = true
				elseif val == "false" then val = false
				end
			end

			if senderToggle._state ~= val then
				senderToggle._state = val
				senderToggle:UpdateColors()
				senderToggle:InvalidateLayout()
			end
		end

		self:RefreshBotStatus()

		if selfRef:IsValid(self.WorkflowStatusPanel) and self.WorkflowStatusPanel.UpdateStatus then
			self.WorkflowStatusPanel:UpdateStatus()
		end

		if selfRef:IsValid(self.AutoSyncButton) then
			local autoSyncStatus = selfRef:GetSetting("Auto_Sync_Global", true) and selfRef:L("mode_on") or selfRef:L("mode_off")
			self.AutoSyncButton:SetText(selfRef:L("menu_auto_sync") .. ": " .. autoSyncStatus)
		end

		self._isUpdating = false
	end

    function PANEL:RefreshBotStatus()
        if game.SinglePlayer() then
            if selfRef:IsValid(self.BotStatusLabel) then
                self.BotStatusLabel:SetText(
                    selfRef:L("solo_mode_title") or "SOLO MODE\n\n" ..
                    selfRef:L("solo_mode_desc") or "Bot companion is not available in single player.\n" ..
                    "Use LLM and TTS to communicate with AI.\n\n" ..
                    "Commands: !ai <question>, !companion spawn <type>"
                )
                self.BotStatusLabel:SetTextColor(Color(100, 200, 255))
            end
            return
        end

        local ply = LocalPlayer()
        if not selfRef:IsValid(ply) or not selfRef:IsValid(self.BotStatusLabel) then
            return
        end

        local bot = selfRef:GetCompanion(ply)
        if selfRef:IsValid(bot) then
            local hp = math.Round(bot:Health())
            local maxHp = math.Round(bot:GetMaxHealth())
            local armor = math.Round(bot:Armor())
            local state = selfRef:GetBotState(bot) or "idle"
            local task = bot:GetNWString("CurrentTask", "")
            local inVeh = bot:InVehicle() and selfRef:L("status_in_vehicle") or selfRef:L("status_on_foot")
            local wep = selfRef:L("status_no_weapon")
            local aw = bot:GetActiveWeapon()
            if selfRef:IsValid(aw) then
                wep = aw:GetClass()
            end

            self.BotStatusLabel:SetText(
                selfRef:L("status_bot_header") .. "\n" ..
                selfRef:L("status_name"):format(bot:Nick() or selfRef:L("unknown")) .. "\n" ..
                selfRef:L("status_health"):format(hp .. "/" .. maxHp) .. " | " .. selfRef:L("status_armor"):format(armor) .. "\n" ..
                selfRef:L("status_state"):format(state, task) .. "\n" ..
                selfRef:L("status_movement"):format(inVeh) .. "\n" ..
                selfRef:L("status_weapon"):format(wep)
            )
            self.BotStatusLabel:SetTextColor(Color(100, 255, 100))
        else
            self.BotStatusLabel:SetText(
                selfRef:L("status_no_bot_header") .. "\n\n" .. selfRef:L("menu_create") .. "\n" .. selfRef:L("cmd_help_create")
            )
            self.BotStatusLabel:SetTextColor(Color(255, 150, 150))
        end
    end

    function PANEL:CreateSection(parent, title)
        local lbl = vgui.Create("DLabel", parent)
        lbl:SetText(title)
        lbl:Dock(TOP)
        lbl:DockMargin(0, 12, 0, 4)
        lbl:SetTall(22)
        lbl:SetTextColor(Color(100, 200, 255))
        lbl:SetFont("DermaDefaultBold")

        local line = vgui.Create("DPanel", parent)
        line:Dock(TOP)
        line:SetTall(1)
        line.Paint = function(s, w, h)
            surface.SetDrawColor(100, 200, 255, 80)
            surface.DrawRect(0, 0, w, h)
        end
        return lbl
    end

    function PANEL:CreateButton(parent, text, tooltip, callback)
        local btn = vgui.Create("DButton", parent)
        btn:SetText(text)
        btn:Dock(TOP)
        btn:DockMargin(0, 2, 0, 2)
        btn:SetTall(28)
        btn:SetTooltip(tooltip or "")
        btn.DoClick = callback
        return btn
    end

	function PANEL:CreateToggle(parent, text, tooltip, default, callback, globalKey, isGlobal)
		isGlobal = isGlobal or false
		local ply = LocalPlayer()
		local isAdmin = ply and ply:GetNWBool("AI_IsAdmin", false) or false

		local pnl = vgui.Create("DPanel", parent)
		pnl:Dock(TOP)
		pnl:DockMargin(0, 2, 0, 2)
		pnl:SetTall(28)
		pnl.Paint = function(s, w, h)
			surface.SetDrawColor(40, 40, 40, 180)
			surface.DrawRect(0, 0, w, h)
		end

		local lbl = vgui.Create("DLabel", pnl)
		lbl:SetText(text)
		lbl:Dock(LEFT)
		lbl:DockMargin(8, 0, 0, 0)
		lbl:SetWide(200)
		lbl:SetTextColor(Color(220, 220, 220))
		if isGlobal then
			lbl:SetTooltip((tooltip or "") .. " (Глобальная настройка)")
		else
			lbl:SetTooltip(tooltip or "")
		end

		local btn = vgui.Create("DButton", pnl)
		btn:Dock(RIGHT)
		btn:DockMargin(0, 2, 12, 2)
		btn:SetWide(60)
		btn:SetText(default and selfRef:L("mode_on") or selfRef:L("mode_off"))
		btn._state = default or false
		btn._key = globalKey
		btn._callback = callback

		if isGlobal and not isAdmin then
			btn:SetEnabled(false)
			btn:SetTooltip("Глобальная настройка (только для администратора)")
		else
			btn:SetEnabled(true)
			if isGlobal then
				btn:SetTooltip("Глобальная настройка (изменяется для всех игроков)")
			else
				btn:SetTooltip(tooltip or "")
			end
		end

		btn.UpdateColors = function(s)
			if s._state then
				s:SetTextColor(Color(100, 255, 100))
				s:SetText(selfRef:L("mode_on"))
			else
				s:SetTextColor(Color(255, 100, 100))
				s:SetText(selfRef:L("mode_off"))
			end
		end
		btn:UpdateColors()

		btn.DoClick = function(s)
			if s._state == nil then return end
			if s._lastClick and (CurTime() - s._lastClick) < 0.5 then return end
			s._lastClick = CurTime()

			
			s._state = not s._state
			s:UpdateColors()
			
			local ply = LocalPlayer()
			if not selfRef:IsValid(ply) then return end

			selfRef:SendSettingToServer(s._key, s._state)
			if s._callback then
				s._callback(s._state)
			end
		end

		if globalKey then
			self.ToggleChecks[globalKey] = btn
		end
		return pnl, btn
	end

	function PANEL:CreateTextEntry(parent, text, tooltip, default, callback, globalKey, isGlobal)
		isGlobal = isGlobal or false
		local ply = LocalPlayer()
		local isAdmin = ply and ply:GetNWBool("AI_IsAdmin", false) or false

		local pnl = vgui.Create("DPanel", parent)
		pnl:Dock(TOP)
		pnl:DockMargin(0, 2, 0, 2)
		pnl:SetTall(28)
		pnl.Paint = function(s, w, h)
			surface.SetDrawColor(40, 40, 40, 180)
			surface.DrawRect(0, 0, w, h)
		end

		local lbl = vgui.Create("DLabel", pnl)
		lbl:SetText(text)
		lbl:Dock(LEFT)
		lbl:DockMargin(8, 0, 0, 0)
		lbl:SetWide(150)
		lbl:SetTextColor(Color(220, 220, 220))
		if isGlobal then
			lbl:SetTooltip((tooltip or "") .. " (Глобальная настройка)")
		else
			lbl:SetTooltip(tooltip or "")
		end

		local entry = vgui.Create("DTextEntry", pnl)
		entry:Dock(FILL)
		entry:DockMargin(4, 2, 8, 2)
		entry:SetText(default or "")
		entry._lastText = default or ""
		entry._updatingFromServer = false

		if isGlobal and not isAdmin then
			entry:SetEditable(false)

			entry:SetTooltip("Глобальная настройка (только для администратора)")
		else
			entry:SetEditable(true)

			if isGlobal then
				entry:SetTooltip("Глобальная настройка (изменяется для всех игроков)")
			else
				entry:SetTooltip(tooltip or "")
			end
		end

		local function ApplyValue(s)
			local txt = s:GetText()
			if callback then
				callback(txt)
			else
				selfRef:SendSettingToServer(globalKey, txt)
			end
		end

		entry.OnEnter = function(s)
			local txt = s:GetText()
			if s._updatingFromServer then return end
			if txt ~= s._lastText then
				s._lastText = txt
				ApplyValue(s)
				s._justEntered = true
			end
		end

		entry.OnLoseFocus = function(s)
			if s._updatingFromServer then return end
			if s._justEntered then
				s._justEntered = false
				return
			end
			local txt = s:GetText()
			if txt ~= s._lastText then
				s._lastText = txt
				ApplyValue(s)
			end
		end

		if globalKey then
			self.InputFields[globalKey] = entry
		end
		return pnl, entry
	end

	function PANEL:CreateModeToggle(parent, label, tooltip, options, callback, key, defaultValue, isGlobal)
		isGlobal = isGlobal or false
		local ply = LocalPlayer()
		local isAdmin = ply and ply:GetNWBool("AI_IsAdmin", false) or false

		local pnl = vgui.Create("DPanel", parent)
		pnl:Dock(TOP)
		pnl:DockMargin(0, 2, 0, 2)
		pnl:SetTall(28)
		pnl.Paint = function(s, w, h)
			surface.SetDrawColor(40, 40, 40, 180)
			surface.DrawRect(0, 0, w, h)
		end

		local lbl = vgui.Create("DLabel", pnl)
		lbl:Dock(FILL)
		lbl:DockMargin(8, 0, 0, 0)
		lbl:SetText(label)
		lbl:SetTextColor(Color(220, 220, 220))
		if isGlobal then
			lbl:SetTooltip((tooltip or "") .. " (Глобальная настройка)")
		else
			lbl:SetTooltip(tooltip or "")
		end
		lbl:SetContentAlignment(4)

		local btnContainer = vgui.Create("DPanel", pnl)
		btnContainer:Dock(RIGHT)
		btnContainer:DockMargin(0, 2, 5, 2)
		btnContainer:SetWide(270)
		btnContainer.Paint = function() end

		local settings = selfRef:GetAllSettings()
		local currentValue = settings[key] or defaultValue or (options[1] and options[1].id)
		local buttons = {}

		for i, opt in ipairs(options) do
			local btn = vgui.Create("DButton", btnContainer)
			btn:Dock(LEFT)
			btn:DockMargin(0, 0, 2, 0)
			btn:SetWide(85)
			btn:SetTall(24)
			btn:SetTooltip(opt.desc or "")
			btn:SetText("")

			if isGlobal and not isAdmin then
				btn:SetEnabled(false)
				btn:SetTooltip("Глобальная настройка (только для администратора)")
			else
				btn:SetEnabled(true)
				if isGlobal then
					btn:SetTooltip("Глобальная настройка (изменяется для всех игроков)")
				end
			end

			btn.Paint = function(s, w, h)
				draw.RoundedBox(4, 0, 0, w, h, Color(22, 22, 25, 220))
				draw.RoundedBox(4, 0, 0, w, h, Color(0, 0, 0, 0), Color(50, 50, 55, 200))
			end
			btn:SetPaintBackground(false)
			btn:SetDrawBorder(false)

			local textLbl = vgui.Create("DLabel", btn)
			textLbl:Dock(FILL)
			textLbl:SetText(opt.name)
			textLbl:SetTextColor(Color(255, 100, 100))
			textLbl:SetContentAlignment(5)

			btn._value = opt.id
			btn._isActive = (opt.id == currentValue)
			btn._key = key
			btn._textLabel = textLbl

			local function UpdateButtonStyle(s)
				if s._isActive then
					s._textLabel:SetTextColor(Color(100, 255, 100))
				else
					s._textLabel:SetTextColor(Color(255, 100, 100))
				end
			end
			UpdateButtonStyle(btn)

			btn.DoClick = function(s)
				if s._isActive then return end
				for _, b in ipairs(buttons) do
					b._isActive = false
					UpdateButtonStyle(b)
				end
				s._isActive = true
				UpdateButtonStyle(s)

				local value = s._value
				selfRef:SendSettingToServer(key, value)
				if callback then
					callback(value)
				end
			end

			table.insert(buttons, btn)
		end

		pnl._buttons = buttons
		pnl._key = key

		pnl.SetValue = function(s, value)
			for _, btn in ipairs(s._buttons) do
				btn._isActive = (btn._value == value)
				UpdateButtonStyle(btn)
			end
		end

		return pnl
	end

    function PANEL:BuildMainTab()
        local scroll = vgui.Create("DScrollPanel")
        self.Sheet:AddSheet(selfRef:L("menu_main"), scroll, "icon16/cog.png")

        local panel = vgui.Create("DPanel", scroll)
        panel:Dock(TOP)
        panel:SetTall(950)
        panel.Paint = function() end

        self:CreateSection(panel, selfRef:L("menu_language"))

        local langPanel = vgui.Create("DPanel", panel)
        langPanel:Dock(TOP)
        langPanel:DockMargin(0, 2, 0, 6)
        langPanel:SetTall(32)
        langPanel.Paint = function(s, w, h)
            surface.SetDrawColor(40, 40, 50, 200)
            surface.DrawRect(0, 0, w, h)
            surface.SetDrawColor(60, 60, 80, 80)
            surface.DrawOutlinedRect(0, 0, w, h)
        end

        local langLbl = vgui.Create("DLabel", langPanel)
        langLbl:SetText(selfRef:L("menu_language") .. ":")
        langLbl:Dock(LEFT)
        langLbl:DockMargin(12, 0, 8, 0)
        langLbl:SetWide(150)
        langLbl:SetTextColor(Color(220, 220, 220))
        langLbl:SetFont("DermaDefaultBold")

        local langCombo = vgui.Create("DComboBox", langPanel)
        langCombo:Dock(FILL)
        langCombo:DockMargin(0, 4, 12, 4)
        langCombo:SetFont("DermaDefault")

        local function UpdateLanguageCombo()
            langCombo:Clear()
            local available = selfRef.locale:GetAvailable()
            local current = selfRef.locale:GetLang()

            local LANG_NAMES = {
                ru = "Русский", en = "English", es = "Español",
                de = "Deutsch", fr = "Français", zh = "中文",
                ja = "日本語", ko = "한국어", pt = "Português",
                it = "Italiano", pl = "Polski", tr = "Türkçe",
                uk = "Українська", cs = "Čeština", sv = "Svenska",
                nl = "Nederlands",
            }

            for _, lang in ipairs(available) do
                local display = LANG_NAMES[lang] or lang
                langCombo:AddChoice(display, lang)
                if lang == current then
                    langCombo:SetText(display)
                end
            end
        end

        UpdateLanguageCombo()

        langCombo.OnSelect = function(combo, index, value, data)
            local lang = data
            if lang and lang ~= selfRef.locale:GetLang() then

                local savedValues = {}
                for key, entry in pairs(self.InputFields) do
                    if selfRef:IsValid(entry) then
                        savedValues[key] = entry:GetText()
                    end
                end

                selfRef.locale:SetLang(lang)
                selfRef:SendSettingToServer("locale", lang)

                if selfRef:IsValid(self.Sheet) then
                    self.Sheet:Clear()
                end

                self:BuildMainTab()
                self:BuildLLMTab()
                self:BuildTTSTab()

                if not game.SinglePlayer() then
                    self:BuildBotTab()
                    self:BuildCombatTab()
                end

                self:BuildAppearanceTab()
                self:BuildInfoTab()
                self:BuildPromptTab()
                self:BuildWorkflowTab()
				self:BuildMemoryTab()
                self:RefreshValues()

                timer.Simple(0.15, function()
                    if not selfRef:IsValid(self) then return end
                    for key, value in pairs(savedValues) do
                        local entry = self.InputFields[key]
                        if selfRef:IsValid(entry) then
                            entry._updatingFromServer = true
                            entry:SetText(value)
                            entry._lastText = value
                            timer.Simple(0.1, function()
                                if selfRef:IsValid(entry) then
                                    entry._updatingFromServer = false
                                end
                            end)
                        end
                    end
                end)

                UpdateLanguageCombo()
                chat.AddText(Color(100, 200, 255), "[AI] " .. selfRef:L("console_locale_loaded"):format(lang))
            end
        end

        self.LangCombo = langCombo
        self.UpdateLanguageCombo = UpdateLanguageCombo

        self:CreateSection(panel, selfRef:L("menu_network"))

        self:CreateTextEntry(panel, selfRef:L("menu_llm_ip"), selfRef:L("tooltip_llm_ip"),
            selfRef:GetSetting("LLM_IP", "127.0.0.1"),
            function(text)
                local ok, err = selfRef.utils:ValidateIP(text)
                if not ok then
                    LocalPlayer():ChatPrint("[" .. selfRef:L("ai_prefix") .. "] " .. selfRef:L("settings_invalid_ip"))
                    return
                end
                selfRef:SendSettingToServer("LLM_IP", text)
            end, "LLM_IP", true)

        self:CreateTextEntry(panel, selfRef:L("menu_llm_port"), selfRef:L("tooltip_llm_port"),
            tostring(selfRef:GetSetting("LLM_Port", 1234)),
            function(text)
                local port = tonumber(text)
                local ok, portNum = selfRef.utils:ValidatePort(port)
                if not ok then
                    LocalPlayer():ChatPrint("[" .. selfRef:L("ai_prefix") .. "] " .. selfRef:L("settings_invalid_port"))
                    return
                end
                selfRef:SendSettingToServer("LLM_Port", portNum)
            end, "LLM_Port", true)

        self:CreateTextEntry(panel, selfRef:L("menu_llm_model"), selfRef:L("tooltip_llm_model"),
            selfRef:GetSetting("LLM_Model", "local-model"),
            function(text)
                selfRef:SendSettingToServer("LLM_Model", text)
            end, "LLM_Model", true)

        self:CreateTextEntry(panel, selfRef:L("menu_tts_ip"), selfRef:L("tooltip_tts_ip"),
            selfRef:GetSetting("TTS_IP", "127.0.0.1"),
            function(text)
                local ok, err = selfRef.utils:ValidateIP(text)
                if not ok then
                    LocalPlayer():ChatPrint("[" .. selfRef:L("ai_prefix") .. "] " .. selfRef:L("settings_invalid_ip"))
                    return
                end
                selfRef:SendSettingToServer("TTS_IP", text)
            end, "TTS_IP", true)

        self:CreateTextEntry(panel, selfRef:L("menu_tts_port"), selfRef:L("tooltip_tts_port"),
            tostring(selfRef:GetSetting("TTS_Port", 8188)),
            function(text)
                local port = tonumber(text)
                local ok, portNum = selfRef.utils:ValidatePort(port)
                if not ok then
                    LocalPlayer():ChatPrint("[" .. selfRef:L("ai_prefix") .. "] " .. selfRef:L("settings_invalid_port"))
                    return
                end
                selfRef:SendSettingToServer("TTS_Port", portNum)
            end, "TTS_Port", true)

        self:CreateTextEntry(panel, selfRef:L("menu_llm_timeout"), selfRef:L("tooltip_llm_timeout"),
            tostring(selfRef:GetSetting("LLM_Timeout", 60)),
            function(text)
                local ply = LocalPlayer()
                if selfRef:IsValid(ply) then
                    local val = tonumber(text)
                    if val and val >= 5 and val <= 300 then
                        selfRef:SendSettingToServer("LLM_Timeout", val)
                    else
                        ply:ChatPrint("[" .. selfRef:L("ai_prefix") .. "] " .. selfRef:L("settings_timeout_invalid"))
                    end
                end
            end, "LLM_Timeout", true)

        self:CreateTextEntry(panel, selfRef:L("menu_tts_timeout"), selfRef:L("tooltip_tts_timeout"),
            tostring(selfRef:GetSetting("TTS_Timeout", 120)),
            function(text)
                local ply = LocalPlayer()
                if selfRef:IsValid(ply) then
                    local val = tonumber(text)
                    if val and val >= 5 and val <= 300 then
                        selfRef:SendSettingToServer("TTS_Timeout", val)
                    else
                        ply:ChatPrint("[" .. selfRef:L("ai_prefix") .. "] " .. selfRef:L("settings_timeout_invalid"))
                    end
                end
            end, "TTS_Timeout", true)

        self:CreateSection(panel, selfRef:L("menu_modes"))

        self:CreateModeToggle(panel, selfRef:L("menu_llm_mode"), selfRef:L("tooltip_llm_mode"),
            {
                { id = "local", name = selfRef:L("llm_local"), desc = selfRef:L("llm_local_desc") },
                { id = "cloud", name = selfRef:L("llm_cloud"), desc = selfRef:L("llm_cloud_desc") },
                { id = "disabled", name = selfRef:L("llm_disabled_status"), desc = selfRef:L("llm_disabled_desc") }
            },
            function(value)
                if value == "local" then
                    selfRef:SendSettingToServer("LLM_Mode", "local")
                    selfRef:SendSettingToServer("LLM_Enabled", true)
                    LocalPlayer():ChatPrint("[" .. selfRef:L("ai_prefix") .. "] " .. selfRef:L("llm_local"))
                elseif value == "cloud" then
                    selfRef:SendSettingToServer("LLM_Mode", "cloud")
                    selfRef:SendSettingToServer("LLM_Enabled", true)
                    LocalPlayer():ChatPrint("[" .. selfRef:L("ai_prefix") .. "] " .. selfRef:L("llm_cloud"))
                else
                    selfRef:SendSettingToServer("LLM_Mode", "disabled")
                    selfRef:SendSettingToServer("LLM_Enabled", false)
                    LocalPlayer():ChatPrint("[" .. selfRef:L("ai_prefix") .. "] " .. selfRef:L("llm_disabled_status"))
                end
                self:RefreshValues()
            end,
            "LLM_Mode", selfRef:GetSetting("LLM_Mode", "local"), true)

        self:CreateModeToggle(panel, selfRef:L("menu_tts_mode"), selfRef:L("tooltip_tts_mode"),
            {
                { id = "local", name = selfRef:L("tts_local"), desc = selfRef:L("tts_local_desc") },
                { id = "cloud", name = selfRef:L("tts_cloud"), desc = selfRef:L("tts_cloud_desc") },
                { id = "disabled", name = selfRef:L("tts_disabled"), desc = selfRef:L("tts_disabled_desc") }
            },
            function(value)
                if value == "local" then
                    selfRef:SendSettingToServer("TTS_Mode", "local")
                    selfRef:SendSettingToServer("TTS_Enabled", true)
                    LocalPlayer():ChatPrint("[" .. selfRef:L("ai_prefix") .. "] " .. selfRef:L("tts_local"))
                elseif value == "cloud" then
                    selfRef:SendSettingToServer("TTS_Mode", "cloud")
                    selfRef:SendSettingToServer("TTS_Enabled", true)
                    LocalPlayer():ChatPrint("[" .. selfRef:L("ai_prefix") .. "] " .. selfRef:L("tts_cloud"))
                else
                    selfRef:SendSettingToServer("TTS_Mode", "disabled")
                    selfRef:SendSettingToServer("TTS_Enabled", false)
                    LocalPlayer():ChatPrint("[" .. selfRef:L("ai_prefix") .. "] " .. selfRef:L("tts_disabled"))
                end
                self:RefreshValues()
            end,
            "TTS_Mode", selfRef:GetSetting("TTS_Mode", "local"), true)

        self:CreateToggle(panel, selfRef:L("menu_tts_personal"), selfRef:L("tooltip_tts_personal"),
            selfRef:GetSetting("TTS_Personal", true),
            function(val)
                selfRef:SendSettingToServer("TTS_Personal", val)
                local state = val and selfRef:L("mode_on") or selfRef:L("mode_off")
                LocalPlayer():ChatPrint("[" .. selfRef:L("ai_prefix") .. "] " .. selfRef:L("tts_personal"):format(state))
            end, "TTS_Personal", false)

		self:CreateToggle(panel, selfRef:L("menu_debug"), selfRef:L("tooltip_debug"),
			selfRef:GetSetting("Debug_Mode", false),
			function(val)
				selfRef:SendSettingToServer("Debug_Mode", val)
				local state = val and selfRef:L("mode_on") or selfRef:L("mode_off")
				selfRef.utils:LogDebug("[AI] " .. selfRef:L("settings_debug"):format(state))
				LocalPlayer():ChatPrint("[" .. selfRef:L("ai_prefix") .. "] " .. selfRef:L("settings_debug"):format(state))

				local locator = _G.AI_GetLocator()
				if locator and locator:has("logger") then
					local logger = locator:get("logger")
					if val then
						logger:SetLevel("DEBUG")
						selfRef.utils:LogDebug("[AI] Уровень логирования: DEBUG")
					else
						logger:SetLevel("INFO")
						selfRef.utils:LogDebug("[AI] Уровень логирования: INFO")
					end
				end
			end, "Debug_Mode", true)

        self:CreateSection(panel, selfRef:L("menu_tools"))

        self:CreateButton(panel, selfRef:L("menu_ping"), selfRef:L("tooltip_ping"),
            function()
                local ply = LocalPlayer()
                if selfRef:IsValid(ply) then
                    RunConsoleCommand("ai_ping_servers")
                end
            end)

        self:CreateButton(panel, selfRef:L("menu_show_models"), selfRef:L("tooltip_show_models"),
            function()
                local models = player_manager.AllValidModels()
                print("")
                print("═══════════════════════════════════════════════════════")
                print("        " .. selfRef:L("menu_show_models"))
                print("═══════════════════════════════════════════════════════")
                print("")

                if not models or next(models) == nil then
                    selfRef.utils:LogDebug("  " .. selfRef:L("no_models_found"))
                else
                    local sorted = {}
                    for name, path in pairs(models) do
                        table.insert(sorted, {name = name, path = path})
                    end
                    table.sort(sorted, function(a, b) return a.name < b.name end)

                    for _, entry in ipairs(sorted) do
						selfRef.utils:LogDebug("  " .. entry.name .. " -> " .. entry.path)
						print("  " .. entry.name .. " -> " .. entry.path)  
                    end
                    selfRef.utils:LogDebug("")

                end
                selfRef.utils:LogDebug("")

                local ply = LocalPlayer()
                if selfRef:IsValid(ply) then
                    ply:ChatPrint("[" .. selfRef:L("ai_prefix") .. "] " .. selfRef:L("models_printed_to_console"))
                end
            end)

        self:CreateButton(panel, selfRef:L("menu_show_status"), selfRef:L("tooltip_show_status"),
            function()
                local ply = LocalPlayer()
                if selfRef:IsValid(ply) then
                    RunConsoleCommand("ai_companion_status")
                end
            end)

        self:CreateButton(panel, selfRef:L("menu_reset"), selfRef:L("tooltip_reset"),
            function()
                Derma_Query(
                    selfRef:L("dialog_reset_text"),
                    selfRef:L("dialog_replace_title"),
                    selfRef:L("dialog_yes"),
                    function()
                        local ply = LocalPlayer()
                        if selfRef:IsValid(ply) then
                            RunConsoleCommand("ai_reset_settings")
                            timer.Simple(0.5, function()
                                if selfRef:IsValid(self) then
                                    self:RefreshValues()
                                    ply:ChatPrint("[" .. selfRef:L("ai_prefix") .. "] " .. selfRef:L("settings_reset"))
                                end
                            end)
                        end
                    end,
                    selfRef:L("dialog_no"),
                    function() end
                )
            end)

        local ply = LocalPlayer()
        if selfRef:IsValid(ply) and ply:IsAdmin() then
            self:CreateSection(panel, selfRef:L("menu_admin"))

            self:CreateButton(panel, selfRef:L("menu_sync_global"), selfRef:L("tooltip_sync_global"),
                function()
                    Derma_Query(
                        selfRef:L("sync_confirm_text"),
                        selfRef:L("dialog_replace_title"),
                        selfRef:L("dialog_yes"),
                        function()
                            LocalPlayer():ConCommand("ai_sync_global")
                        end,
                        selfRef:L("dialog_no"),
                        function() end
                    )
                end)

				local autoSyncStatus = selfRef:GetSetting("Auto_Sync_Global", true) and selfRef:L("mode_on") or selfRef:L("mode_off")
				self.AutoSyncButton = self:CreateButton(panel,
					selfRef:L("menu_auto_sync") .. ": " .. autoSyncStatus,
					selfRef:L("tooltip_auto_sync"),
					function()
						LocalPlayer():ConCommand("ai_auto_sync")

						timer.Simple(0.5, function()
							if selfRef:IsValid(self) then
								self:RefreshValues()
							end
						end)
					end)
				end

        self:CreateSection(panel, selfRef:L("menu_status"))

        local statusPanel = vgui.Create("DPanel", panel)
        statusPanel:Dock(TOP)
        statusPanel:DockMargin(8, 4, 8, 8)
        statusPanel:SetTall(140)
        statusPanel.Paint = function(s, w, h)
            surface.SetDrawColor(25, 25, 35, 220)
            surface.DrawRect(0, 0, w, h)
            surface.SetDrawColor(60, 60, 80, 100)
            surface.DrawOutlinedRect(0, 0, w, h)

            local settings = selfRef:GetAllSettings()
            local llmStatus = ""
            if settings.llm_enabled == false then
                llmStatus = selfRef:L("llm_disabled_status")
            elseif settings.llm_mode == "cloud" then
                llmStatus = selfRef:L("llm_cloud")
            else
                llmStatus = selfRef:L("llm_local")
            end

            local ttsStatus = ""
            if settings.tts_enabled == false then
                ttsStatus = selfRef:L("tts_disabled")
            elseif settings.tts_mode == "cloud" then
                ttsStatus = selfRef:L("tts_cloud")
            else
                ttsStatus = selfRef:L("tts_local")
            end

            local personalStatus = settings.tts_personal and selfRef:L("mode_on") or selfRef:L("mode_off")
            local debugStatus = settings.debug_mode and selfRef:L("mode_on") or selfRef:L("mode_off")
            local langStatus = selfRef.locale:GetLang() == "ru" and "Русский" or
                              selfRef.locale:GetLang() == "en" and "English" or
                              selfRef.locale:GetLang()

            draw.SimpleText(selfRef:L("menu_llm_status"):format(llmStatus), "DermaDefault", 12, 12, Color(200, 200, 200))
            draw.SimpleText(selfRef:L("menu_tts_status"):format(ttsStatus, personalStatus), "DermaDefault", 12, 34, Color(200, 200, 200))
            draw.SimpleText(selfRef:L("menu_debug_status"):format(debugStatus), "DermaDefault", 12, 56, Color(200, 200, 200))
            draw.SimpleText(selfRef:L("menu_language") .. ": " .. langStatus, "DermaDefault", 12, 78, Color(200, 200, 200))
            draw.SimpleText("LLM Timeout: " .. tostring(settings.llm_timeout or 60) .. "s | TTS Timeout: " .. tostring(settings.tts_timeout or 120) .. "s", "DermaDefault", 12, 100, Color(180, 180, 200))
        end

		local statusTimer = 0
		statusPanel.Think = function(s)
			statusTimer = statusTimer + FrameTime()
			if statusTimer > 1.0 then
				statusTimer = 0
				s:InvalidateLayout()
			end
		end
    end

    function PANEL:BuildLLMTab()
        local scroll = vgui.Create("DScrollPanel")
        self.Sheet:AddSheet(selfRef:L("menu_llm"), scroll, "icon16/world.png")

        local panel = vgui.Create("DPanel", scroll)
        panel:Dock(TOP)
        panel:SetTall(500)
        panel.Paint = function() end

        local warn = vgui.Create("DLabel", panel)
        warn:SetText(" " .. selfRef:L("llm_local_hint"))
        warn:Dock(TOP)
        warn:DockMargin(8, 4, 8, 4)
        warn:SetTall(24)
        warn:SetTextColor(Color(255, 200, 100))
        warn:SetFont("DermaDefaultBold")

        self:CreateSection(panel, selfRef:L("menu_cloud_llm"))

        local providerList = {
            { id = "openai", name = "OpenAI (ChatGPT)", needsKey = true },
            { id = "deepseek", name = "DeepSeek", needsKey = true },
            { id = "anthropic", name = "Anthropic (Claude)", needsKey = true },
            { id = "google", name = "Google Gemini", needsKey = true },
            { id = "grok", name = "Grok (xAI)", needsKey = true }
        }

        local providerPanel = vgui.Create("DPanel", panel)
        providerPanel:Dock(TOP)
        providerPanel:DockMargin(8, 4, 8, 4)
        providerPanel:SetTall(32)
        providerPanel.Paint = function(s, w, h)
            surface.SetDrawColor(40, 40, 40, 180)
            surface.DrawRect(0, 0, w, h)
        end

        local providerLbl = vgui.Create("DLabel", providerPanel)
        providerLbl:SetText(selfRef:L("menu_provider"))
        providerLbl:Dock(LEFT)
        providerLbl:DockMargin(8, 0, 8, 0)
        providerLbl:SetWide(80)
        providerLbl:SetTextColor(Color(220, 220, 220))

        local providerCombo = vgui.Create("DComboBox", providerPanel)
        providerCombo:Dock(FILL)
        providerCombo:DockMargin(0, 2, 8, 2)

        local currentProvider = selfRef:GetSetting("LLM_Provider", "openai")
        for _, p in ipairs(providerList) do
            providerCombo:AddChoice(p.name, p)
            if p.id == currentProvider then
                providerCombo:SetText(p.name)
            end
        end

        providerCombo.OnSelect = function(combo, index, value, data)
            local provider = data
            if not provider then return end
            selfRef:SendSettingToServer("LLM_Provider", provider.id)
            self:RefreshValues()
        end

        self:CreateTextEntry(panel, selfRef:L("menu_api_key"), selfRef:L("tooltip_llm_api_key"),
            selfRef:GetSetting("LLM_API_Key", ""),
            function(text)
                selfRef:SendSettingToServer("LLM_API_Key", text)
            end, "LLM_API_Key", true)

        self:CreateTextEntry(panel, selfRef:L("menu_cloud_model"), selfRef:L("tooltip_llm_cloud_model"),
            selfRef:GetSetting("LLM_Cloud_Model", ""),
            function(text)
                selfRef:SendSettingToServer("LLM_Cloud_Model", text)
            end, "LLM_Cloud_Model", true)

        self:CreateTextEntry(panel, selfRef:L("menu_endpoint"), selfRef:L("tooltip_llm_endpoint"),
            selfRef:GetSetting("LLM_Endpoint", ""),
            function(text)
                selfRef:SendSettingToServer("LLM_Endpoint", text)
            end, "LLM_Endpoint", true)

        self:CreateButton(panel, selfRef:L("menu_test_connection"), selfRef:L("tooltip_test_llm"),
            function()
                local ply = LocalPlayer()
                if selfRef:IsValid(ply) then
                    RunConsoleCommand("ai_test_llm")
                    chat.AddText(Color(100, 200, 255), "[AI] " .. selfRef:L("llm_testing"))
                    selfRef.utils:LogDebug("[AI MENU] " .. selfRef:L("llm_testing"))
                end
            end)
    end

    function PANEL:BuildTTSTab()
        local scroll = vgui.Create("DScrollPanel")
        self.Sheet:AddSheet(selfRef:L("menu_tts"), scroll, "icon16/sound.png")

        local panel = vgui.Create("DPanel", scroll)
        panel:Dock(TOP)
        panel:SetTall(750)
        panel.Paint = function() end

        local warn = vgui.Create("DLabel", panel)
        warn:SetText(" " .. selfRef:L("tts_local_hint"))
        warn:Dock(TOP)
        warn:DockMargin(8, 4, 8, 4)
        warn:SetTall(24)
        warn:SetTextColor(Color(255, 200, 100))
        warn:SetFont("DermaDefaultBold")

        self:CreateSection(panel, selfRef:L("menu_cloud_tts"))

        local providerList = {
            { id = "elevenlabs", name = "ElevenLabs", needsKey = true },
            { id = "google", name = "Google Cloud TTS", needsKey = true },
            { id = "yandex", name = "Yandex SpeechKit (MP3)", needsKey = true, needsFolder = true },
            { id = "vk", name = "VK Cloud Voice (MP3)", needsKey = true }
        }

        local providerPanel = vgui.Create("DPanel", panel)
        providerPanel:Dock(TOP)
        providerPanel:DockMargin(8, 4, 8, 4)
        providerPanel:SetTall(32)
        providerPanel.Paint = function(s, w, h)
            surface.SetDrawColor(40, 40, 40, 180)
            surface.DrawRect(0, 0, w, h)
        end

        local providerLbl = vgui.Create("DLabel", providerPanel)
        providerLbl:SetText(selfRef:L("menu_provider"))
        providerLbl:Dock(LEFT)
        providerLbl:DockMargin(8, 0, 8, 0)
        providerLbl:SetWide(80)
        providerLbl:SetTextColor(Color(220, 220, 220))

        local providerCombo = vgui.Create("DComboBox", providerPanel)
        providerCombo:Dock(FILL)
        providerCombo:DockMargin(0, 2, 8, 2)

        local currentProvider = selfRef:GetSetting("TTS_Provider", "elevenlabs")
        for _, p in ipairs(providerList) do
            providerCombo:AddChoice(p.name, p)
            if p.id == currentProvider then
                providerCombo:SetText(p.name)
            end
        end

        providerCombo.OnSelect = function(combo, index, value, data)
            local provider = data
            if not provider then return end
            selfRef:SendSettingToServer("TTS_Provider", provider.id)
            self:RefreshValues()
        end

        self:CreateSection(panel, selfRef:L("menu_common_settings"))

        self:CreateTextEntry(panel, selfRef:L("menu_api_key"), selfRef:L("tooltip_tts_api_key"),
            selfRef:GetSetting("TTS_API_Key", ""),
            function(text)
                selfRef:SendSettingToServer("TTS_API_Key", text)
            end, "TTS_API_Key", true)

        self:CreateTextEntry(panel, selfRef:L("menu_endpoint"), selfRef:L("tooltip_tts_endpoint"),
            selfRef:GetSetting("TTS_Endpoint", ""),
            function(text)
                selfRef:SendSettingToServer("TTS_Endpoint", text)
            end, "TTS_Endpoint", true)

        self:CreateSection(panel, "ElevenLabs")

        self:CreateTextEntry(panel, selfRef:L("menu_voice"), selfRef:L("tooltip_elevenlabs_voice"),
            selfRef:GetSetting("TTS_Voice", ""),
            function(text)
                selfRef:SendSettingToServer("TTS_Voice", text)
            end, "TTS_Voice", true)

        self:CreateSection(panel, "Google Cloud TTS")

        self:CreateTextEntry(panel, selfRef:L("menu_language"), selfRef:L("tooltip_google_lang"),
            selfRef:GetSetting("TTS_Language", ""),
            function(text)
                selfRef:SendSettingToServer("TTS_Language", text)
            end, "TTS_Language", true)

        self:CreateTextEntry(panel, selfRef:L("menu_voice"), selfRef:L("tooltip_google_voice"),
            selfRef:GetSetting("TTS_Voice", ""),
            function(text)
                selfRef:SendSettingToServer("TTS_Voice", text)
            end, "TTS_Voice", true)

        self:CreateSection(panel, "Yandex SpeechKit")

        self:CreateTextEntry(panel, selfRef:L("menu_yandex_folder"), selfRef:L("tooltip_yandex_folder"),
            selfRef:GetSetting("Yandex_Folder_ID", ""),
            function(text)
                selfRef:SendSettingToServer("Yandex_Folder_ID", text)
            end, "Yandex_Folder_ID", true)

        self:CreateTextEntry(panel, selfRef:L("menu_yandex_voice"), selfRef:L("tooltip_yandex_voice"),
            selfRef:GetSetting("Yandex_Voice", "oksana"),
            function(text)
                selfRef:SendSettingToServer("Yandex_Voice", text)
            end, "Yandex_Voice", true)

        self:CreateTextEntry(panel, selfRef:L("menu_yandex_lang"), selfRef:L("tooltip_yandex_lang"),
            selfRef:GetSetting("Yandex_Lang", "ru-RU"),
            function(text)
                selfRef:SendSettingToServer("Yandex_Lang", text)
            end, "Yandex_Lang", true)

        self:CreateSection(panel, "VK Cloud Voice")

        self:CreateTextEntry(panel, selfRef:L("menu_vk_voice"), selfRef:L("tooltip_vk_voice"),
            selfRef:GetSetting("VK_Voice", "katherine"),
            function(text)
                selfRef:SendSettingToServer("VK_Voice", text)
            end, "VK_Voice", true)

        self:CreateTextEntry(panel, selfRef:L("menu_vk_tempo"), selfRef:L("tooltip_vk_tempo"),
            tostring(selfRef:GetSetting("VK_Tempo", 1.0)),
            function(text)
                local tempo = tonumber(text)
                if tempo and tempo >= 0.75 and tempo <= 1.75 then
                    selfRef:SendSettingToServer("VK_Tempo", tempo)
                else
                    LocalPlayer():ChatPrint("[AI] " .. selfRef:L("vk_tempo_invalid"))
                end
            end, "VK_Tempo", true)

        self:CreateSection(panel, selfRef:L("menu_tools"))

        self:CreateButton(panel, selfRef:L("menu_test_tts"), selfRef:L("tooltip_test_tts"),
            function()
                local ply = LocalPlayer()
                if selfRef:IsValid(ply) then
                    RunConsoleCommand("ai_test_tts")
                    chat.AddText(Color(100, 200, 255), "[AI] " .. selfRef:L("tts_testing"))
                    selfRef.utils:LogDebug("[AI MENU] " .. selfRef:L("tts_testing"))
                end
            end)
    end

	function PANEL:BuildBotTab()
		if game.SinglePlayer() then return end

		local scroll = vgui.Create("DScrollPanel")
		self.Sheet:AddSheet(selfRef:L("menu_bot"), scroll, "icon16/user.png")

		local panel = vgui.Create("DPanel", scroll)
		panel:Dock(TOP)
		panel:SetTall(500)
		panel.Paint = function() end

		self:CreateSection(panel, selfRef:L("menu_bot_creation"))

		self:CreateButton(panel, selfRef:L("menu_create"), selfRef:L("tooltip_create"),
			function()
				local ply = LocalPlayer()
				if not selfRef:IsValid(ply) then return end
				if selfRef:HasCompanion(ply) then
					local bot = selfRef:GetCompanion(ply)
					local name = selfRef:IsValid(bot) and bot:Nick() or selfRef:L("unknown")
					Derma_Query(
						selfRef:L("dialog_replace_text"):format(name),
						selfRef:L("dialog_replace_title"),
						selfRef:L("dialog_yes"),
						function()
							self:RunCommand("ai_companion_remove")
							timer.Simple(0.5, function()
								self:RunCommand("ai_companion_create")
							end)
						end,
						selfRef:L("dialog_no"),
						function() end
					)
				else
					self:RunCommand("ai_companion_create")
				end
			end)

		self:CreateButton(panel, selfRef:L("menu_remove"), selfRef:L("tooltip_remove"),
			function()
				local ply = LocalPlayer()
				if not selfRef:IsValid(ply) then return end
				if not selfRef:HasCompanion(ply) then
					ply:ChatPrint("[" .. selfRef:L("ai_prefix") .. "] " .. selfRef:L("bot_not_found"))
					return
				end
				Derma_Query(
					selfRef:L("dialog_remove_text"),
					selfRef:L("dialog_replace_title"),
					selfRef:L("dialog_yes"),
					function()
						self:RunCommand("ai_companion_remove")
					end,
					selfRef:L("dialog_no"),
					function() end
				)
			end)

		self:CreateButton(panel, selfRef:L("menu_replace"), selfRef:L("tooltip_replace"),
			function()
				local ply = LocalPlayer()
				if not selfRef:IsValid(ply) then return end
				if not selfRef:HasCompanion(ply) then
					ply:ChatPrint("[" .. selfRef:L("ai_prefix") .. "] " .. selfRef:L("bot_not_found"))
					return
				end
				local bot = selfRef:GetCompanion(ply)
				local name = selfRef:IsValid(bot) and bot:Nick() or selfRef:L("unknown")
				Derma_Query(
					selfRef:L("dialog_replace_text"):format(name),
					selfRef:L("dialog_replace_title"),
					selfRef:L("dialog_yes"),
					function()
						self:RunCommand("ai_companion_replace")
					end,
					selfRef:L("dialog_no"),
					function() end
				)
			end)

		self:CreateSection(panel, selfRef:L("menu_bot_settings"))

		local settings = selfRef:GetAllSettings()

		self:CreateTextEntry(panel, selfRef:L("menu_name"), selfRef:L("tooltip_nick"),
			settings.Companion_Nick or "AI_Companion",
			function(text)
				local ply = LocalPlayer()
				if not selfRef:IsValid(ply) then return end
				text = string.Trim(text)
				if text == "" then
					ply:ChatPrint("[AI] " .. selfRef:L("settings_nick_empty"))
					return
				end
				local maxNickLen = 32
				if selfRef.config then
					local ui = selfRef.config:get("UI") or {}
					maxNickLen = ui.MaxNickLength or 32
				end
				if #text > maxNickLen then
					text = string.sub(text, 1, maxNickLen)
				end
				selfRef:SendSettingToServer("Companion_Nick", text)
				local bot = selfRef:GetCompanion(ply)
				if selfRef:IsValid(bot) then
					pcall(function() bot:SetName(text) end)
					pcall(function() bot:SetNick(text) end)
				end
			end, "Companion_Nick", false)

		self:CreateTextEntry(panel, selfRef:L("menu_model"), selfRef:L("tooltip_model"),
			settings.Model_Path or "models/player/urban.mdl",
			function(text)
				local ply = LocalPlayer()
				if selfRef:IsValid(ply) then
					selfRef:SendSettingToServer("Model_Path", text)
					local bot = selfRef:GetCompanion(ply)
					if selfRef:IsValid(bot) then
						pcall(function() bot:SetModel(text) end)
					end
				end
			end, "Model_Path", false)

		self:CreateSection(panel, selfRef:L("menu_bot_control"))

		self:CreateButton(panel, selfRef:L("menu_follow"), selfRef:L("tooltip_follow"),
			function()
				LocalPlayer():ConCommand("say !companion follow")
			end)
		self:CreateButton(panel, selfRef:L("menu_point"), selfRef:L("tooltip_point"),
			function()
				LocalPlayer():ConCommand("say !companion point")
			end)
		self:CreateButton(panel, selfRef:L("menu_stop"), selfRef:L("tooltip_stop"),
			function()
				LocalPlayer():ConCommand("say !companion stop")
			end)
		self:CreateButton(panel, selfRef:L("menu_attack"), selfRef:L("tooltip_attack"),
			function()
				LocalPlayer():ConCommand("say !companion attack")
			end)
		self:CreateButton(panel, selfRef:L("menu_sit"), selfRef:L("tooltip_sit"),
			function()
				LocalPlayer():ConCommand("say !companion sit")
			end)
		self:CreateButton(panel, selfRef:L("menu_standup"), selfRef:L("tooltip_standup"),
			function()
				LocalPlayer():ConCommand("say !companion standup")
			end)
		self:CreateButton(panel, selfRef:L("menu_teleport"), selfRef:L("tooltip_teleport"),
			function()
				self:RunCommand("ai_companion_teleport")
			end)
	end

	function PANEL:BuildCombatTab()
		if game.SinglePlayer() then return end

		local scroll = vgui.Create("DScrollPanel")
		self.Sheet:AddSheet(selfRef:L("menu_combat"), scroll, "icon16/gun.png")

		local panel = vgui.Create("DPanel", scroll)
		panel:Dock(TOP)
		panel:SetTall(500)
		panel.Paint = function() end

		self:CreateSection(panel, selfRef:L("menu_weapons"))

		local settings = selfRef:GetAllSettings()

		self:CreateTextEntry(panel, selfRef:L("menu_combat_weapon"), selfRef:L("tooltip_combat_weapon"),
			settings.Combat_Weapon or "weapon_smg1",
			function(text)
				local ply = LocalPlayer()
				if not selfRef:IsValid(ply) then return end
				text = string.Trim(text)
				if text == "" then
					ply:ChatPrint("[AI] " .. selfRef:L("settings_weapon_empty"))
					return
				end
				selfRef:SendSettingToServer("Combat_Weapon", text)
				ply:ChatPrint("[AI] Боевое оружие установлено: " .. text)
			end, "Combat_Weapon", false)

		self:CreateTextEntry(panel, selfRef:L("menu_melee_weapon"), selfRef:L("tooltip_melee_weapon"),
			settings.Melee_Weapon or "weapon_crowbar",
			function(text)
				local ply = LocalPlayer()
				if not selfRef:IsValid(ply) then return end
				text = string.Trim(text)
				if text == "" then
					ply:ChatPrint("[AI] " .. selfRef:L("settings_weapon_empty"))
					return
				end
				selfRef:SendSettingToServer("Melee_Weapon", text)
				ply:ChatPrint("[AI] Оружие ближнего боя установлено: " .. text)
			end, "Melee_Weapon", false)

		self:CreateTextEntry(panel, selfRef:L("menu_idle_weapon"), selfRef:L("tooltip_idle_weapon"),
			settings.Idle_Weapon or "weapon_physgun",
			function(text)
				local ply = LocalPlayer()
				if not selfRef:IsValid(ply) then return end
				text = string.Trim(text)
				if text == "" then
					ply:ChatPrint("[AI] " .. selfRef:L("settings_weapon_empty"))
					return
				end
				selfRef:SendSettingToServer("Idle_Weapon", text)
				ply:ChatPrint("[AI] Мирное оружие установлено: " .. text)
			end, "Idle_Weapon", false)

		self:CreateSection(panel, selfRef:L("menu_behavior"))

		self:CreateToggle(panel, selfRef:L("menu_stealth"), selfRef:L("tooltip_stealth"),
			settings.Stealth_Mode or false,
			function(val)
				local ply = LocalPlayer()
				if selfRef:IsValid(ply) then
					local state = val and selfRef:L("mode_on") or selfRef:L("mode_off")
					ply:ChatPrint("[" .. selfRef:L("ai_prefix") .. "] " .. selfRef:L("mode_stealth"):format(state))
				end
			end, "Stealth_Mode", false)

		self:CreateToggle(panel, selfRef:L("menu_pacifist"), selfRef:L("tooltip_pacifist"),
			settings.Pacifist_Mode or false,
			function(val)
				local ply = LocalPlayer()
				if selfRef:IsValid(ply) then
					local state = val and selfRef:L("mode_on") or selfRef:L("mode_off")
					ply:ChatPrint("[" .. selfRef:L("ai_prefix") .. "] " .. selfRef:L("mode_pacifist"):format(state))
				end
			end, "Pacifist_Mode", false)

		self:CreateToggle(panel, selfRef:L("menu_aggressive"), selfRef:L("tooltip_aggressive"),
			settings.Aggressive_Mode or false,
			function(val)
				local ply = LocalPlayer()
				if selfRef:IsValid(ply) then
					local state = val and selfRef:L("mode_on") or selfRef:L("mode_off")
					ply:ChatPrint("[" .. selfRef:L("ai_prefix") .. "] " .. selfRef:L("mode_aggressive"):format(state))
				end
			end, "Aggressive_Mode", false)

		self:CreateToggle(panel, selfRef:L("menu_defender"), selfRef:L("tooltip_defender"),
			settings.Defender_Mode or false,
			function(val)
				local ply = LocalPlayer()
				if selfRef:IsValid(ply) then
					local state = val and selfRef:L("mode_on") or selfRef:L("mode_off")
					ply:ChatPrint("[" .. selfRef:L("ai_prefix") .. "] " .. selfRef:L("mode_defender"):format(state))
				end
			end, "Defender_Mode", false)

		self:CreateToggle(panel, selfRef:L("menu_medic"), selfRef:L("tooltip_medic"),
			settings.Medic_Mode or false,
			function(val)
				local ply = LocalPlayer()
				if selfRef:IsValid(ply) then
					local state = val and selfRef:L("mode_on") or selfRef:L("mode_off")
					ply:ChatPrint("[" .. selfRef:L("ai_prefix") .. "] " .. selfRef:L("mode_medic"):format(state))
				end
			end, "Medic_Mode", false)
	end

    function PANEL:BuildAppearanceTab()
        local scroll = vgui.Create("DScrollPanel")
        self.Sheet:AddSheet(selfRef:L("menu_appearance"), scroll, "icon16/palette.png")

        local panel = vgui.Create("DPanel", scroll)
        panel:Dock(TOP)
        panel:SetTall(1200)
        panel.Paint = function() end

        self:CreateSection(panel, selfRef:L("menu_appearance_prefix"))

        self:CreateTextEntry(panel, selfRef:L("menu_prefix_text"), selfRef:L("tooltip_prefix_text"),
            selfRef:GetSetting("Prefix_Text", "[AI]"),
            function(text)
                local ply = LocalPlayer()
                if not selfRef:IsValid(ply) then return end
                text = string.Trim(text)
                if text == "" then
                    ply:ChatPrint("[AI] " .. selfRef:L("settings_prefix_empty"))
                    return
                end
                text = string.gsub(text, "[<>\"'&]", "")
                selfRef:SendSettingToServer("Prefix_Text", text)
            end, "Prefix_Text", false)

        self:CreateSection(panel, selfRef:L("menu_personalization"))

		self:CreateToggle(panel, selfRef:L("menu_show_sender_name"), selfRef:L("tooltip_show_sender"),
			selfRef:GetSetting("Show_Sender_Name", true),
			function(val)
				local state = val and selfRef:L("mode_on") or selfRef:L("mode_off")
				LocalPlayer():ChatPrint("[" .. selfRef:L("ai_prefix") .. "] " .. selfRef:L("menu_show_sender_name") .. ": " .. state)

			end, "Show_Sender_Name", false)

		local examplePanel = vgui.Create("DPanel", panel)
		examplePanel:Dock(TOP)
		examplePanel:DockMargin(8, 2, 8, 4)
		examplePanel:SetTall(28)
		examplePanel.Paint = function(s, w, h)
			surface.SetDrawColor(30, 30, 40, 150)
			surface.DrawRect(0, 0, w, h)
			
			local settings = selfRef:GetAllSettings()
			
			
			local showName = settings.Show_Sender_Name
			if showName == nil then showName = true end
			
			local prefix = settings.Prefix_Text or "[AI]"
			local cleanPrefix = string.gsub(prefix, "^%[", "")
			cleanPrefix = string.gsub(cleanPrefix, "%]$", "")
			if cleanPrefix == "" then cleanPrefix = "AI" end
			
			local exampleText
			if showName then
				exampleText = selfRef:L("example_with_name"):format(cleanPrefix)
			else
				exampleText = selfRef:L("example_without_name"):format(cleanPrefix)
			end
			
			draw.SimpleText(selfRef:L("menu_example"), "DermaDefault", 8, h/2, Color(150, 150, 150), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			draw.SimpleText(exampleText, "DermaDefault", 70, h/2, Color(100, 200, 255), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		examplePanel.Think = function(s)
			s:InvalidateLayout()
		end

		self:CreateSection(panel, selfRef:L("menu_prefix_color"))

		self:CreateTextEntry(panel, selfRef:L("menu_red"), selfRef:L("tooltip_color"),
			tostring(selfRef:GetSetting("Prefix_Color_R", 255)),
			function(text)
				local ply = LocalPlayer()
				if selfRef:IsValid(ply) then
					local val = tonumber(text)
					if val and val >= 0 and val <= 255 then
						selfRef:SendSettingToServer("Prefix_Color_R", val)

					end
				end
			end, "Prefix_Color_R", false)

		self:CreateTextEntry(panel, selfRef:L("menu_green"), selfRef:L("tooltip_color"),
			tostring(selfRef:GetSetting("Prefix_Color_G", 200)),
			function(text)
				local ply = LocalPlayer()
				if selfRef:IsValid(ply) then
					local val = tonumber(text)
					if val and val >= 0 and val <= 255 then
						selfRef:SendSettingToServer("Prefix_Color_G", val)

					end
				end
			end, "Prefix_Color_G", false)

		self:CreateTextEntry(panel, selfRef:L("menu_blue"), selfRef:L("tooltip_color"),
			tostring(selfRef:GetSetting("Prefix_Color_B", 0)),
			function(text)
				local ply = LocalPlayer()
				if selfRef:IsValid(ply) then
					local val = tonumber(text)
					if val and val >= 0 and val <= 255 then
						selfRef:SendSettingToServer("Prefix_Color_B", val)

					end
				end
			end, "Prefix_Color_B", false)

        self:CreateToggle(panel, selfRef:L("menu_rainbow_prefix"), selfRef:L("tooltip_rainbow"),
            selfRef:GetSetting("Prefix_Rainbow", false),
            function(val)
                local ply = LocalPlayer()
                if selfRef:IsValid(ply) then
                    selfRef:SendSettingToServer("Prefix_Rainbow", val)
                    local state = val and selfRef:L("mode_on") or selfRef:L("mode_off")
                    ply:ChatPrint("[" .. selfRef:L("ai_prefix") .. "] " .. selfRef:L("settings_rainbow"):format(state))
                end
            end, "Prefix_Rainbow", false)

        self:CreateSection(panel, selfRef:L("menu_preview"))

		local preview = vgui.Create("DPanel", panel)
		preview:Dock(TOP)
		preview:DockMargin(8, 4, 8, 4)
		preview:SetTall(40)
		preview.Paint = function(s, w, h)
			local settings = selfRef:GetAllSettings()
			local prefix = settings.Prefix_Text or "[AI]"
			
			
			local r = settings.Prefix_Color_R or 255
			local g = settings.Prefix_Color_G or 200
			local b = settings.Prefix_Color_B or 0
			local rainbow = settings.Prefix_Rainbow or false
			
			if rainbow then
				local col = HSVToColor((CurTime() * 60) % 360, 1, 1)
				r, g, b = col.r, col.g, col.b
			end
			
			local cleanPrefix = string.gsub(prefix, "^%[", "")
			cleanPrefix = string.gsub(cleanPrefix, "%]$", "")
			if cleanPrefix == "" then cleanPrefix = "AI" end
			
			local showName = settings.Show_Sender_Name
			if showName == nil then showName = true end
			
			local displayText
			if showName then
				displayText = selfRef:L("preview_with_name"):format(cleanPrefix)
			else
				displayText = selfRef:L("preview_without_name"):format(cleanPrefix)
			end
			
			draw.SimpleText(displayText, "DermaDefaultBold", w/2, h/2, Color(r, g, b), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		preview.Think = function(s)
			s:InvalidateLayout()
		end

        self:CreateSection(panel, selfRef:L("menu_quick_colors"))

        local colors = {
            {selfRef:L("menu_quick_standard"), "255 200 0"},
            {selfRef:L("color_white"), "255 255 255"},
            {selfRef:L("color_black"), "30 30 30"},
            {selfRef:L("color_gray"), "150 150 150"},
            {selfRef:L("color_red"), "255 50 50"},
            {selfRef:L("color_dark_red"), "180 0 0"},
            {selfRef:L("color_orange"), "255 150 0"},
            {selfRef:L("color_yellow"), "255 255 0"},
            {selfRef:L("color_lime"), "150 255 50"},
            {selfRef:L("color_green"), "50 255 50"},
            {selfRef:L("color_dark_green"), "0 150 0"},
            {selfRef:L("color_cyan"), "0 255 255"},
            {selfRef:L("color_light_blue"), "50 200 255"},
            {selfRef:L("color_blue"), "50 100 255"},
            {selfRef:L("color_dark_blue"), "0 50 180"},
            {selfRef:L("color_purple"), "150 50 255"},
            {selfRef:L("color_pink"), "255 100 200"},
            {selfRef:L("color_magenta"), "255 0 255"},
            {selfRef:L("color_brown"), "150 100 50"},
            {selfRef:L("color_chat"), "255 255 178"},
            {selfRef:L("color_admin_red"), "255 0 0"},
            {selfRef:L("color_gold"), "255 215 0"},
            {selfRef:L("color_silver"), "192 192 192"},
        }

        for _, col in ipairs(colors) do
            self:CreateButton(panel, col[1], selfRef:L("tooltip_set_color"):format(col[2]), function()
                local rgb = string.Explode(" ", col[2])
                local ply = LocalPlayer()
                if selfRef:IsValid(ply) then
                    local r, g, b = tonumber(rgb[1]), tonumber(rgb[2]), tonumber(rgb[3])
                    selfRef:SendSettingToServer("Prefix_Color_R", r)
                    selfRef:SendSettingToServer("Prefix_Color_G", g)
                    selfRef:SendSettingToServer("Prefix_Color_B", b)
                    self:RefreshValues()
                end
            end)
        end
    end

	function PANEL:BuildMemoryTab()
		local scroll = vgui.Create("DScrollPanel")
		self.Sheet:AddSheet(selfRef:L("menu_memory") or "Память", scroll, "icon16/script_edit.png")

		local panel = vgui.Create("DPanel", scroll)
		panel:Dock(TOP)
		panel:SetTall(800)
		panel.Paint = function() end

		self:CreateSection(panel, selfRef:L("menu_memory_settings") or "Настройки памяти")

		self:CreateToggle(panel, selfRef:L("menu_memory_enabled") or "Включить память",
			selfRef:L("tooltip_memory_enabled") or "Позволяет боту запоминать сообщения и события",
			selfRef:GetSetting("Memory_Enabled", true),
			function(val)
				selfRef:SendSettingToServer("Memory_Enabled", val)
				net.Start("AI_Remember_Toggle")
				net.WriteBool(val)
				net.SendToServer()
			end, "Memory_Enabled", true)

		self:CreateSection(panel, selfRef:L("menu_memory_data") or "Журнал памяти")

		local info = vgui.Create("DLabel", panel)
		info:SetText("Здесь отображается то, что бот 'помнит' о игроках. Данные обновляются автоматически.")
		info:Dock(TOP)
		info:DockMargin(8, 4, 8, 4)
		info:SetTall(20)
		info:SetWrap(true)
		info:SetTextColor(Color(180, 180, 180))

		local textContainer = vgui.Create("DPanel", panel)
		textContainer:Dock(TOP)
		textContainer:DockMargin(8, 4, 8, 4)
		textContainer:SetTall(450)
		textContainer.Paint = function(s, w, h)
			surface.SetDrawColor(20, 20, 25, 240)
			surface.DrawRect(0, 0, w, h)
			surface.SetDrawColor(60, 60, 80, 100)
			surface.DrawOutlinedRect(0, 0, w, h)
		end

		local memoryLog = vgui.Create("DTextEntry", textContainer)
		memoryLog:Dock(FILL)
		memoryLog:DockMargin(4, 4, 4, 4)
		memoryLog:SetMultiline(true)
		memoryLog:SetVerticalScrollbarEnabled(true)
		memoryLog:SetFont("DermaDefault")
		memoryLog:SetTextColor(Color(200, 220, 255))
		memoryLog:SetPaintBackground(false)
		memoryLog:SetEditable(false)
		memoryLog:SetCursorColor(Color(0,0,0,0))
		memoryLog:SetText("Нажмите 'Обновить', чтобы загрузить журнал...")

		local btnPanel = vgui.Create("DPanel", panel)
		btnPanel:Dock(TOP)
		btnPanel:DockMargin(8, 4, 8, 4)
		btnPanel:SetTall(32)
		btnPanel.Paint = function() end

		local refreshBtn = vgui.Create("DButton", btnPanel)
		refreshBtn:Dock(LEFT)
		refreshBtn:SetWide(150)
		refreshBtn:SetText(selfRef:L("menu_memory_refresh") or "Обновить журнал")
		refreshBtn.DoClick = function()
			net.Start("AI_Remember_RequestLog")
			net.SendToServer()
			memoryLog:SetText("Загрузка...")
		end

		local clearBtn = vgui.Create("DButton", btnPanel)
		clearBtn:Dock(LEFT)
		clearBtn:DockMargin(8, 0, 0, 0)
		clearBtn:SetWide(150)
		clearBtn:SetText(selfRef:L("menu_memory_clear") or "Очистить всю память")
		clearBtn:SetTextColor(Color(255, 100, 100))
		clearBtn.DoClick = function()
			Derma_Query(
				selfRef:L("dialog_clear_memory") or "Очистить всю память бота?",
				selfRef:L("dialog_replace_title") or "Подтверждение",
				selfRef:L("dialog_yes") or "Да",
				function()
					net.Start("AI_Remember_Clear")
					net.SendToServer()
					timer.Simple(0.5, function()
						net.Start("AI_Remember_RequestLog")
						net.SendToServer()
					end)
				end,
				selfRef:L("dialog_no") or "Нет",
				function() end
			)
		end

		if not self._memoryNetSetup then
			self._memoryNetSetup = true
			net.Receive("AI_Remember_SendLog", function()
				local logText = net.ReadString()
				if _G.AICompanionMenuPanel and _G.AICompanionMenuPanel.MemoryLog then
					_G.AICompanionMenuPanel.MemoryLog:SetText(logText)
				end
			end)
		end

		self.MemoryLog = memoryLog
	end
    function PANEL:BuildInfoTab()
        local scroll = vgui.Create("DScrollPanel")
        self.Sheet:AddSheet(selfRef:L("menu_info"), scroll, "icon16/information.png")

        local panel = vgui.Create("DPanel", scroll)
        panel:Dock(TOP)
        panel:SetTall(650)
        panel.Paint = function() end

        if not game.SinglePlayer() then
            self:CreateSection(panel, selfRef:L("menu_status"))
            self.BotStatusLabel = vgui.Create("DLabel", panel)
            self.BotStatusLabel:Dock(TOP)
            self.BotStatusLabel:DockMargin(8, 4, 8, 8)
            self.BotStatusLabel:SetTall(150)
            self.BotStatusLabel:SetWrap(true)
            self.BotStatusLabel:SetTextColor(Color(200, 200, 200))
            self.BotStatusLabel:SetFont("DermaDefault")
            self:RefreshBotStatus()

            self:CreateButton(panel, selfRef:L("menu_show_status"), selfRef:L("tooltip_refresh_status"),
                function()
                    self:RefreshBotStatus()
                end)
        end

        self:CreateSection(panel, selfRef:L("menu_about"))

        local about = vgui.Create("DLabel", panel)
        about:SetText(selfRef:L("menu_about_text"))
        about:Dock(TOP)
        about:DockMargin(8, 4, 8, 4)
        about:SetTall(350)
        about:SetWrap(true)
        about:SetTextColor(Color(0, 191, 255))
        about:SetFont("DermaDefault")
    end

	function PANEL:BuildPromptTab()
		local scroll = vgui.Create("DScrollPanel")
		self.Sheet:AddSheet(selfRef:L("menu_prompt") or "Prompt", scroll, "icon16/script_edit.png")

		local panel = vgui.Create("DPanel", scroll)
		panel:Dock(TOP)
		panel:SetTall(700)
		panel.Paint = function() end

		self:CreateSection(panel, selfRef:L("menu_prompt_custom") or "Custom Prompt")

		local settings = selfRef:GetAllSettings()

		self:CreateToggle(panel, selfRef:L("menu_prompt_enabled") or "Use custom prompt",
			selfRef:L("tooltip_prompt_enabled") or "Enable/disable custom system prompt",
			settings.Custom_Prompt_Enabled or false,
			function(val)
				selfRef:SendSettingToServer("Custom_Prompt_Enabled", val)
				local state = val and selfRef:L("mode_on") or selfRef:L("mode_off")
				LocalPlayer():ChatPrint("[" .. selfRef:L("ai_prefix") .. "] " .. (selfRef:L("prompt_enabled") or "Custom prompt") .. ": " .. state)
			end, "Custom_Prompt_Enabled", false)

		local sysInfo = vgui.Create("DLabel", panel)
		sysInfo:SetText(selfRef:L("menu_prompt_system_info") or "When custom prompt is disabled, the standard system prompt is used.")
		sysInfo:Dock(TOP)
		sysInfo:DockMargin(8, 4, 8, 8)
		sysInfo:SetTall(40)
		sysInfo:SetWrap(true)
		sysInfo:SetTextColor(Color(0, 191, 255))
		sysInfo:SetFont("DermaDefault")

		local sep = vgui.Create("DPanel", panel)
		sep:Dock(TOP)
		sep:DockMargin(8, 4, 8, 8)
		sep:SetTall(1)
		sep.Paint = function(s, w, h)
			surface.SetDrawColor(60, 60, 80, 100)
			surface.DrawRect(0, 0, w, h)
		end

		self:CreateSection(panel, selfRef:L("menu_prompt_editor") or "Prompt Editor")

		local textContainer = vgui.Create("DPanel", panel)
		textContainer:Dock(TOP)
		textContainer:DockMargin(8, 4, 8, 4)
		textContainer:SetTall(300)
		textContainer.Paint = function(s, w, h)
			surface.SetDrawColor(30, 30, 35, 220)
			surface.DrawRect(0, 0, w, h)
			surface.SetDrawColor(60, 60, 80, 80)
			surface.DrawOutlinedRect(0, 0, w, h)
		end

		local promptEntry = vgui.Create("DTextEntry", textContainer)
		promptEntry:Dock(FILL)
		promptEntry:DockMargin(4, 4, 4, 4)
		promptEntry:SetMultiline(true)
		promptEntry:SetVerticalScrollbarEnabled(true)

		promptEntry:SetText(settings.Custom_Prompt_Text or "")

		promptEntry:SetFont("DermaDefault")
		promptEntry:SetTextColor(Color(220, 220, 220))
		promptEntry:SetPaintBackground(false)
		promptEntry:SetUpdateOnType(true)
		promptEntry._lastText = settings.Custom_Prompt_Text or ""
		promptEntry._updatingFromServer = false

		local charCount = vgui.Create("DLabel", panel)
		charCount:Dock(TOP)
		charCount:DockMargin(8, 4, 8, 4)
		charCount:SetTall(20)
		charCount:SetTextColor(Color(150, 150, 150))
		charCount:SetFont("DermaDefault")

		local function UpdateCharCount()
			local text = promptEntry:GetText() or ""
			local count = #text
			local maxLen = 8000
			local color = count > maxLen and Color(255, 100, 100) or Color(150, 150, 150)
			charCount:SetTextColor(color)
			charCount:SetText((selfRef:L("prompt_chars") or "Characters: ") .. count .. " / " .. maxLen)
		end

		promptEntry.OnValueChange = function(s)
			if s._updatingFromServer then return end
			UpdateCharCount()
		end

		promptEntry.OnLoseFocus = function(s)
			if s._updatingFromServer then
				s._updatingFromServer = false
				return
			end
			local text = s:GetText()
			if text ~= s._lastText then
				s._lastText = text
				if #text > 8000 then
					text = string.sub(text, 1, 8000)
					s:SetText(text)
					s._lastText = text
				end
				selfRef:SendSettingToServer("Custom_Prompt_Text", text)
				UpdateCharCount()
			end
		end

		local btnPanel = vgui.Create("DPanel", panel)
		btnPanel:Dock(TOP)
		btnPanel:DockMargin(8, 4, 8, 4)
		btnPanel:SetTall(32)
		btnPanel.Paint = function() end

		local saveBtn = vgui.Create("DButton", btnPanel)
		saveBtn:Dock(LEFT)
		saveBtn:SetWide(120)
		saveBtn:SetText(selfRef:L("prompt_save") or "Save")
		saveBtn.DoClick = function()
			local text = promptEntry:GetText()
			if #text > 8000 then
				text = string.sub(text, 1, 8000)
				promptEntry:SetText(text)
			end
			selfRef:SendSettingToServer("Custom_Prompt_Text", text)
			promptEntry._lastText = text
			UpdateCharCount()
			LocalPlayer():ChatPrint("[" .. selfRef:L("ai_prefix") .. "] " .. (selfRef:L("prompt_saved") or "Prompt saved"))
		end

		local resetBtn = vgui.Create("DButton", btnPanel)
		resetBtn:Dock(LEFT)
		resetBtn:DockMargin(8, 0, 0, 0)
		resetBtn:SetWide(120)
		resetBtn:SetText(selfRef:L("prompt_reset") or "Reset")
		resetBtn.DoClick = function()
			Derma_Query(
				selfRef:L("dialog_reset_prompt") or "Reset custom prompt? The standard system prompt will be used.",
				selfRef:L("dialog_replace_title") or "Confirm",
				selfRef:L("dialog_yes") or "Yes",
				function()
					promptEntry:SetText("")
					promptEntry._lastText = ""
					selfRef:SendSettingToServer("Custom_Prompt_Text", "")
					UpdateCharCount()
					LocalPlayer():ChatPrint("[" .. selfRef:L("ai_prefix") .. "] " .. (selfRef:L("prompt_reset_done") or "Prompt reset"))
				end,
				selfRef:L("dialog_no") or "No",
				function() end
			)
		end

		self.InputFields["Custom_Prompt_Text"] = promptEntry
		UpdateCharCount()

		local ply = LocalPlayer()
		if selfRef:IsValid(ply) and ply:IsAdmin() then
			self:CreateSection(panel, selfRef:L("menu_prompt_admin") or "Admin Settings")
			self:CreateToggle(panel, selfRef:L("menu_prompt_allow_custom") or "Allow custom prompts for players",
				selfRef:L("tooltip_prompt_allow_custom") or "Enable/disable custom prompts for regular players",
				selfRef:GetSetting("Allow_Custom_Prompts", true),
				function(val)
					selfRef:SendSettingToServer("Allow_Custom_Prompts", val)
					local state = val and selfRef:L("mode_on") or selfRef:L("mode_off")
					LocalPlayer():ChatPrint("[" .. selfRef:L("ai_prefix") .. "] " .. (selfRef:L("prompt_allow_custom") or "Custom prompts for players") .. ": " .. state)
				end, "Allow_Custom_Prompts", true)

			local adminInfo = vgui.Create("DLabel", panel)
			adminInfo:SetText(selfRef:L("menu_prompt_admin_info") or "When disabled, regular players cannot change their prompt. Admins can always change it.")
			adminInfo:Dock(TOP)
			adminInfo:DockMargin(8, 4, 8, 8)
			adminInfo:SetTall(50)
			adminInfo:SetWrap(true)
			adminInfo:SetTextColor(Color(0, 191, 255))
			adminInfo:SetFont("DermaDefault")
		end

		local warn = vgui.Create("DLabel", panel)
		warn:SetText(selfRef:L("menu_prompt_warn") or "Long prompts may increase response time and token usage. Recommended length: up to 2000 characters.")
		warn:Dock(TOP)
		warn:DockMargin(8, 8, 8, 4)
		warn:SetTall(40)
		warn:SetWrap(true)
		warn:SetTextColor(Color(255, 200, 100))
		warn:SetFont("DermaDefaultBold")
	end

    function PANEL:BuildWorkflowTab()
        local scroll = vgui.Create("DScrollPanel")
        self.Sheet:AddSheet(selfRef:L("menu_workflow") or "Workflow", scroll, "icon16/bricks.png")

        local panel = vgui.Create("DPanel", scroll)
        panel:Dock(TOP)
        panel:SetTall(600)
        panel.Paint = function() end

        local ply = LocalPlayer()
        if not selfRef:IsValid(ply) or not ply:IsAdmin() then
            local noAccess = vgui.Create("DLabel", panel)
            noAccess:SetText(selfRef:L("menu_workflow_no_access") or "Admin Only")
            noAccess:Dock(TOP)
            noAccess:DockMargin(8, 20, 8, 4)
            noAccess:SetTall(30)
            noAccess:SetTextColor(Color(255, 100, 100))
            noAccess:SetFont("DermaDefaultBold")
            noAccess:SetContentAlignment(5)

            local info = vgui.Create("DLabel", panel)
            info:SetText(selfRef:L("menu_workflow_admin_only") or "Workflow management is only available to server admins.")
            info:Dock(TOP)
            info:DockMargin(8, 4, 8, 4)
            info:SetTall(30)
            info:SetTextColor(Color(0, 191, 255))
            info:SetFont("DermaDefault")
            info:SetContentAlignment(5)
            return
        end

        self:CreateSection(panel, selfRef:L("menu_workflow_manage") or "Workflow Management")

        local statusPanel = vgui.Create("DPanel", panel)
        statusPanel:Dock(TOP)
        statusPanel:DockMargin(8, 4, 8, 8)
        statusPanel:SetTall(80)
        self.WorkflowStatusPanel = statusPanel
        statusPanel._lastEnabled = nil
        statusPanel._lastFilename = nil

        statusPanel.Paint = function(s, w, h)
            surface.SetDrawColor(25, 25, 35, 220)
            surface.DrawRect(0, 0, w, h)
            surface.SetDrawColor(60, 60, 80, 100)
            surface.DrawOutlinedRect(0, 0, w, h)

			 local settings = selfRef:GetAllSettings()

			 local enabled = settings.TTS_Workflow_Enabled or false
			 local filename = settings.TTS_Workflow_Filename or settings.tts_workflow_filename or (selfRef:L("workflow_none") or "Not loaded")

            local statusText = enabled and (selfRef:L("workflow_status_on") or "ON") or (selfRef:L("workflow_status_off") or "OFF")
            local statusColor = enabled and Color(100, 255, 100) or Color(255, 100, 100)

            if s._lastEnabled ~= enabled or s._lastFilename ~= filename then
                s._lastEnabled = enabled
                s._lastFilename = filename
            end

            draw.SimpleText(
                (selfRef:L("workflow_current") or "Current workflow:") .. " " .. filename,
                "DermaDefault",
                12, 12,
                Color(200, 200, 200)
            )
            draw.SimpleText(
                (selfRef:L("workflow_status") or "Status:") .. " " .. statusText,
                "DermaDefault",
                12, 34,
                statusColor
            )
            draw.SimpleText(
                (selfRef:L("workflow_provider") or "Provider:") .. " ComfyUI (Local TTS)",
                "DermaDefault",
                12, 56,
                Color(0, 191, 255)
            )
        end

        statusPanel.Think = function(s)
            s:InvalidateLayout()
        end

        function statusPanel:UpdateStatus()
            self:InvalidateLayout()
        end

        self:CreateButton(panel, selfRef:L("menu_workflow_load") or "Load workflow from file",
            selfRef:L("tooltip_workflow_load") or "Load JSON workflow from file (data/)",
            function()
                local frame = vgui.Create("DFrame")
                frame:SetTitle(selfRef:L("workflow_load_title") or "Load Workflow")
                frame:SetSize(400, 150)
                frame:Center()
                frame:MakePopup()
                frame:SetDraggable(true)
                frame:ShowCloseButton(true)

                local lbl = vgui.Create("DLabel", frame)
                lbl:SetText(selfRef:L("workflow_load_path") or "File path (relative to data/):")
                lbl:SetPos(10, 35)
                lbl:SetWide(380)
                lbl:SetTextColor(Color(220, 220, 220))

                local entry = vgui.Create("DTextEntry", frame)
                entry:SetPos(10, 60)
                entry:SetSize(380, 24)
                entry:SetText("ai_workflow.json")

                local loadBtn = vgui.Create("DButton", frame)
                loadBtn:SetText(selfRef:L("dialog_yes") or "Load")
                loadBtn:SetPos(10, 100)
                loadBtn:SetSize(180, 28)
                loadBtn.DoClick = function()
                    local path = entry:GetText()
                    if path and path ~= "" then
                        LocalPlayer():ConCommand('ai_tts_workflow_load "' .. path .. '"')
                        timer.Simple(0.3, function()
                            if selfRef:IsValid(self) and selfRef:IsValid(self.WorkflowStatusPanel) then
                                self.WorkflowStatusPanel:UpdateStatus()
                            end
                        end)
                    end
                    frame:Close()
                end

                local cancelBtn = vgui.Create("DButton", frame)
                cancelBtn:SetText(selfRef:L("dialog_no") or "Cancel")
                cancelBtn:SetPos(210, 100)
                cancelBtn:SetSize(180, 28)
                cancelBtn.DoClick = function()
                    frame:Close()
                end
            end)

        self:CreateButton(panel, selfRef:L("menu_workflow_toggle") or "Toggle workflow",
            selfRef:L("tooltip_workflow_toggle") or "Enable/disable custom workflow",
            function()
                LocalPlayer():ConCommand("ai_tts_workflow_toggle")
                timer.Simple(0.3, function()
                    if selfRef:IsValid(self) then
                        self:RefreshValues()
                        if selfRef:IsValid(self.WorkflowStatusPanel) then
                            self.WorkflowStatusPanel:UpdateStatus()
                        end
                    end
                end)
            end)

        self:CreateButton(panel, selfRef:L("menu_workflow_reset") or "Reset to default",
            selfRef:L("tooltip_workflow_reset") or "Reset workflow to default OmniVoice",
            function()
                Derma_Query(
                    selfRef:L("dialog_reset_workflow") or "Reset workflow to default?",
                    selfRef:L("dialog_replace_title") or "Confirm",
                    selfRef:L("dialog_yes") or "Yes",
                    function()
                        LocalPlayer():ConCommand("ai_tts_workflow_reset")
                        timer.Simple(0.3, function()
                            if selfRef:IsValid(self) then
                                self:RefreshValues()
                                if selfRef:IsValid(self.WorkflowStatusPanel) then
                                    self.WorkflowStatusPanel:UpdateStatus()
                                end
                            end
                        end)
                    end,
                    selfRef:L("dialog_no") or "No",
                    function() end
                )
            end)

        self:CreateButton(panel, selfRef:L("menu_workflow_status") or "Show status",
            selfRef:L("tooltip_workflow_status") or "Show current workflow status in chat",
            function()
                LocalPlayer():ConCommand("ai_tts_workflow_status")
            end)

        self:CreateSection(panel, selfRef:L("menu_workflow_info") or "Information")

        local infoText = vgui.Create("DLabel", panel)
        infoText:SetText(selfRef:L("menu_workflow_info_text") or [[
Workflow is a JSON file with ComfyUI node configuration for TTS generation.
Supported formats:
• UI Format (Unsaved Workflow.json) — from ComfyUI interface
• API Format — already converted for API
Default workflow uses OmniVoiceVoiceCloneTTS node.
When loading custom workflow, the text will be automatically
inserted into the appropriate text field.
Console commands:
• ai_tts_workflow_load <path> — load workflow
• ai_tts_workflow_toggle — enable/disable
• ai_tts_workflow_reset — reset to default
• ai_tts_workflow_status — show status
        ]])
        infoText:Dock(TOP)
        infoText:DockMargin(8, 4, 8, 8)
        infoText:SetTall(280)
        infoText:SetWrap(true)
        infoText:SetTextColor(Color(0, 191, 255))
        infoText:SetFont("DermaDefault")
    end

    
    vgui.Register("AICompanionMenu", PANEL, "DFrame")

    
    self._panelClass = PANEL
end





function Menu:Open()
    if not CLIENT then return end

    if self:IsValid(_G.AICompanionMenuPanel) then
        _G.AICompanionMenuPanel:Remove()
        _G.AICompanionMenuPanel = nil
    end

    _G.AICompanionMenuPanel = vgui.Create("AICompanionMenu")
    
    _G.AICompanionMenuPanel._menuRef = self
end





function Menu:SetupNetReceivers()
    if not CLIENT then return end

    local selfRef = self

    net.Receive("AI_TTS_Global_Status", function()
        local status = net.ReadBool()
        selfRef:SendSettingToServer("TTS_Enabled", status)

        if selfRef:IsValid(_G.AICompanionMenuPanel) then
            _G.AICompanionMenuPanel:RefreshValues()
        end

        chat.AddText(Color(100, 200, 255), "[AI] TTS " .. (status and selfRef:L("mode_on") or selfRef:L("mode_off")) .. " " .. selfRef:L("tts_global_status"))
    end)

	

	net.Receive("AI_Settings_Sync", function()
		if selfRef:IsValid(_G.AICompanionMenuPanel) then
			if not _G.AICompanionMenuPanel._isUpdating then
				_G.AICompanionMenuPanel:RefreshValues()
			end
		end
	end)

	net.Receive("AICompanion_ConfigSync", function()
		if selfRef:IsValid(_G.AICompanionMenuPanel) then
			if not _G.AICompanionMenuPanel._isUpdating then
				_G.AICompanionMenuPanel:RefreshValues()
			end
		end
	end)

	net.Receive("AI_PlayerSettings_Sync", function()
		local json = net.ReadString()
		if not json or #json == 0 or #json > 65535 then return end
		local ok, settings = pcall(util.JSONToTable, json)
		if ok and settings and type(settings) == "table" then
			local ply = LocalPlayer()
			if selfRef:IsValid(ply) and selfRef.state then
				local steamID = ply:SteamID64()
				
				selfRef.state:setPlayerSettings(steamID, settings)
				
				selfRef._settingsCache = nil
				selfRef._settingsCacheTime = nil
			end
		end
		
		if selfRef:IsValid(_G.AICompanionMenuPanel) then
			if not _G.AICompanionMenuPanel._isUpdating then
				_G.AICompanionMenuPanel:RefreshValues()
			end
		end
	end)
end




function Menu:GetAPI()
    return {
        Open = function() return self:Open() end,
        Refresh = function()
            if self:IsValid(_G.AICompanionMenuPanel) then
                _G.AICompanionMenuPanel:RefreshValues()
            end
        end,
        GetSettings = function() return self:GetAllSettings() end,
        SendSetting = function(key, value) return self:SendSettingToServer(key, value) end,
        GetCompanion = function(ply) return self:GetCompanion(ply) end,
        HasCompanion = function(ply) return self:HasCompanion(ply) end,
    }
end

return Menu
