if AI_COMPANION_MENU_LOADED then return end
AI_COMPANION_MENU_LOADED = true
if CLIENT then
local AC = _G.AI_COMPANION
if AC then
    if not AC.Settings then
        AC.Settings = AI_SETTINGS or {}
    elseif AI_SETTINGS and AC.Settings ~= AI_SETTINGS then
        for k, v in pairs(AI_SETTINGS) do
            AC.Settings[k] = v
        end
        AI_SETTINGS = AC.Settings
    end
end
if not _G.L or type(_G.L.Get) ~= "function" then
    if _G._L and type(_G._L.Get) == "function" then
        _G.L = _G._L
    else
        _G.L = { Get = function(s,k) return k end }
    end
end
local L = _G.L
local function SendSettingToServer(key, value)
    if CLIENT then
        if AC.Settings then 
            AC.Settings[key] = value 
        end
        if AI_SETTINGS then
            AI_SETTINGS[key] = value
        end
        if key == "tts_enabled" or key == "tts_mode" then
            local ttsEnabled = AC.Settings.tts_enabled
            local ttsMode = AC.Settings.tts_mode
            local isTTSEnabled = (ttsEnabled == true) and (ttsMode ~= "disabled")
            if isTTSEnabled then
                RunConsoleCommand("ai_tts_global_on")
            else
                RunConsoleCommand("ai_tts_global_off")
            end
            return
        end
        if key == "tts_global" then
            if value then RunConsoleCommand("ai_tts_global_on") else RunConsoleCommand("ai_tts_global_off") end
            return
        end
        net.Start("AICompanion_SetSetting")
        net.WriteString(key)
        net.WriteString(tostring(value))
        net.SendToServer()
        if key == "llm_ip" then _G.AI_LLM_IP = value end
        if key == "llm_port" then _G.AI_LLM_PORT = tonumber(value) end
        if key == "llm_model" then _G.AI_LLM_MODEL = value end
        if key == "comfyui_ip" then _G.AI_COMFYUI_IP = value end
        if key == "comfyui_port" then _G.AI_COMFYUI_PORT = tonumber(value) end
        if key == "tts_enabled" then _G.AI_Companion_TTS_Enabled = value end
        if key == "llm_enabled" then _G.AI_Companion_LLM_Enabled = value end
        if key == "prefix_text" then _G.AI_Companion_PrefixText = value end
        if key == "prefix_r" then _G.AI_Companion_PrefixColorR = tonumber(value) end
        if key == "prefix_g" then _G.AI_Companion_PrefixColorG = tonumber(value) end
        if key == "prefix_b" then _G.AI_Companion_PrefixColorB = tonumber(value) end
        if key == "prefix_rainbow" then _G.AI_Companion_PrefixRainbow = value end
    end
end
function GetCompanion(ply)
    if not IsValid(ply) then return nil end
    for _, bot in ipairs(player.GetAll()) do
        if IsValid(bot) and bot:GetNWBool("IsAICompanion", false) then
            local owner = bot:GetNWEntity("AICompanionOwnerEnt")
            if IsValid(owner) and owner == ply then 
                return bot 
            end
        end
    end
    return nil
end
function HasCompanion(ply)
    if not IsValid(ply) then return false end
    return IsValid(GetCompanion(ply))
end
function GetBotState(bot)
    if not IsValid(bot) then return "idle" end
    return bot:GetNWString("BotState", "idle")
end
function GetAllCompanions()
    local bots = {}
    for _, bot in ipairs(player.GetAll()) do
        if IsValid(bot) and bot:GetNWBool("IsAICompanion", false) then
            table.insert(bots, bot)
        end
    end
    return bots
end
local IS_SOLO = game.SinglePlayer()
local PANEL = {}
PANEL.InputFields = {}
PANEL.ToggleChecks = {}
PANEL.LangCombo = nil
PANEL.UpdateLanguageCombo = nil
function PANEL:RunCommand(cmd)
    local ply = LocalPlayer()
    if IsValid(ply) then
        ply:ConCommand(cmd)
    end
end
function PANEL:Init()
    self:SetTitle(L:Get("menu_title"))
    self:SetSize(800, 600)
    self:Center()
    self:MakePopup()
    if CLIENT then RunConsoleCommand("ai_request_settings") end
    self.Sheet = vgui.Create("DPropertySheet", self)
    self.Sheet:Dock(FILL)
    self.AutoSyncButton = nil
    self.Sheet:DockMargin(5, 5, 5, 5)
    self:BuildMainTab()
    self:BuildLLMTab()
    self:BuildTTSTab()
    if not IS_SOLO then
        self:BuildBotTab()
        self:BuildCombatTab()
    end
    self:BuildAppearanceTab()
    self:BuildInfoTab()
    self:BuildPromptTab()
    self:BuildWorkflowTab()
    timer.Simple(0.1, function()
        if IsValid(self) then self:RefreshValues() end
    end)
end
function PANEL:RefreshAllTabs()
    local savedValues = {}
    for key, entry in pairs(self.InputFields) do
        if IsValid(entry) then savedValues[key] = entry:GetText() end
    end
    if IsValid(self.Sheet) then self.Sheet:Clear() end
    self:BuildMainTab()
    self:BuildLLMTab()
    self:BuildTTSTab()
    if not IS_SOLO then
        self:BuildBotTab()
        self:BuildCombatTab()
    end
    self:BuildAppearanceTab()
    self:BuildInfoTab()
    self:BuildPromptTab()
    self:BuildWorkflowTab()
    self:RefreshValues()
    timer.Simple(0.15, function()
        if not IsValid(self) then return end
        for key, value in pairs(savedValues) do
            local entry = self.InputFields[key]
            if IsValid(entry) then
                entry._updatingFromServer = true
                entry:SetText(value)
                entry._lastText = value
                timer.Simple(0.1, function() if IsValid(entry) then entry._updatingFromServer = false end end)
            end
        end
    end)
    if self.UpdateLanguageCombo then self:UpdateLanguageCombo() end
end
function PANEL:RefreshValues()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    local settings
    if IS_SOLO and AI_SETTINGS then
        settings = AI_SETTINGS
        if AC and AC.Settings then
            for k, v in pairs(AI_SETTINGS) do
                AC.Settings[k] = v
            end
        end
    else
        settings = AI_SETTINGS or AC.Settings or {}
    end
    for key, entry in pairs(self.InputFields) do
        if IsValid(entry) then
            if entry:IsEditing() then continue end
            local val = settings[key]
            if val ~= nil then
                entry._updatingFromServer = true
                entry._lastText = tostring(val)
                entry:SetText(tostring(val))
                timer.Simple(0.5, function() 
                    if IsValid(entry) then 
                        entry._updatingFromServer = false 
                    end 
                end)
            end
        end
    end
    for key, btn in pairs(self.ToggleChecks) do
        if IsValid(btn) then
            local val = settings[key]
            if val ~= nil then
                btn._state = val
                btn:UpdateColors()
                btn:InvalidateLayout()
            end
        end
    end
    self:RefreshBotStatus()
    if IsValid(self.WorkflowStatusPanel) and self.WorkflowStatusPanel.UpdateStatus then
        self.WorkflowStatusPanel:UpdateStatus()
    end
end
function PANEL:RefreshBotStatus()
    if IS_SOLO then
        if IsValid(self.BotStatusLabel) then
            self.BotStatusLabel:SetText(
                L:Get("solo_mode_title") or "SOLO MODE\n\n" ..
                L:Get("solo_mode_desc") or "Bot companion is not available in single player.\n" ..
                "Use LLM and TTS to communicate with AI.\n\n" ..
                "Commands: !ai <question>, !companion spawn <type>"
            )
            self.BotStatusLabel:SetTextColor(Color(100, 200, 255))
        end
        return
    end
    local ply = LocalPlayer()
    if not IsValid(ply) or not IsValid(self.BotStatusLabel) then return end
    local bot = GetCompanion(ply)
    if IsValid(bot) then
        local hp = math.Round(bot:Health())
        local maxHp = math.Round(bot:GetMaxHealth())
        local armor = math.Round(bot:Armor())
        local state = GetBotState(bot) or "idle"
        local task = bot:GetNWString("CurrentTask", "")
        local inVeh = bot:InVehicle() and L:Get("status_in_vehicle") or L:Get("status_on_foot")
        local wep = L:Get("status_no_weapon")
        local aw = bot:GetActiveWeapon()
        if IsValid(aw) then wep = aw:GetClass() end
        self.BotStatusLabel:SetText(
            L:Get("status_bot_header") .. "\n" ..
            L:Get("status_name"):format(bot:Nick() or L:Get("unknown")) .. "\n" ..
            L:Get("status_health"):format(hp .. "/" .. maxHp) .. " | " .. L:Get("status_armor"):format(armor) .. "\n" ..
            L:Get("status_state"):format(state, task) .. "\n" ..
            L:Get("status_movement"):format(inVeh) .. "\n" ..
            L:Get("status_weapon"):format(wep)
        )
        self.BotStatusLabel:SetTextColor(Color(100, 255, 100))
    else
        self.BotStatusLabel:SetText(
            L:Get("status_no_bot_header") .. "\n\n" .. L:Get("menu_create") .. "\n" .. L:Get("cmd_help_create")
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
function PANEL:CreateToggle(parent, text, tooltip, default, callback, globalKey)
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
    lbl:SetTooltip(tooltip or "")
    local btn = vgui.Create("DButton", pnl)
    btn:Dock(RIGHT)
    btn:DockMargin(0, 2, 12, 2)
    btn:SetWide(60)
    btn:SetText(default and L:Get("mode_on") or L:Get("mode_off"))
    btn._state = default or false
    btn._key = globalKey
    btn._callback = callback
    btn.UpdateColors = function(s)
        if s._state then
            s:SetTextColor(Color(100, 255, 100))
            s:SetText(L:Get("mode_on"))
        else
            s:SetTextColor(Color(255, 100, 100))
            s:SetText(L:Get("mode_off"))
        end
    end
    btn:UpdateColors()
    btn.DoClick = function(s)
        s._state = not s._state
        s:UpdateColors()
        local ply = LocalPlayer()
        if not IsValid(ply) then return end
        SendSettingToServer(s._key, s._state)
        if AC.Settings then AC.Settings[s._key] = s._state end
        if s._callback then s._callback(s._state) end
    end
    if globalKey then self.ToggleChecks[globalKey] = btn end
    return pnl, btn
end
function PANEL:CreateTextEntry(parent, text, tooltip, default, callback, globalKey)
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
    lbl:SetTooltip(tooltip or "")
    local entry = vgui.Create("DTextEntry", pnl)
    entry:Dock(FILL)
    entry:DockMargin(4, 2, 8, 2)
    entry:SetText(default or "")
    entry._lastText = default or ""
    entry._updatingFromServer = false
    entry.OnEnter = function(s)
        local txt = s:GetText()
        if s._updatingFromServer then return end
        if txt ~= s._lastText then
            s._lastText = txt
            if IsValid(LocalPlayer()) and globalKey then
                SendSettingToServer(globalKey, txt)
                if AC.Settings then AC.Settings[globalKey] = txt end
            end
            if callback then callback(txt) end
        end
    end
    entry.OnLoseFocus = function(s)
        if s._updatingFromServer then
            s._updatingFromServer = false
            return
        end
        local txt = s:GetText()
        if txt ~= s._lastText then
            s._lastText = txt
            if IsValid(LocalPlayer()) and globalKey then
                SendSettingToServer(globalKey, txt)
                if AC.Settings then AC.Settings[globalKey] = txt end
            end
            if callback then callback(txt) end
        end
    end
    if globalKey then self.InputFields[globalKey] = entry end
    return pnl, entry
end
function PANEL:CreateModeToggle(parent, label, tooltip, options, callback, key, defaultValue)
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
    lbl:SetTooltip(tooltip or "")
    lbl:SetContentAlignment(4)
    local btnContainer = vgui.Create("DPanel", pnl)
    btnContainer:Dock(RIGHT)
    btnContainer:DockMargin(0, 2, 5, 2)
    btnContainer:SetWide(270)
    btnContainer.Paint = function() end
    local currentValue = AC.Settings[key] or defaultValue or (options[1] and options[1].id)
    local buttons = {}
    for i, opt in ipairs(options) do
        local btn = vgui.Create("DButton", btnContainer)
        btn:Dock(LEFT)
        btn:DockMargin(0, 0, 2, 0)
        btn:SetWide(85)
        btn:SetTall(24)
        btn:SetTooltip(opt.desc or "")
        btn:SetText("")
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
            for _, b in ipairs(buttons) do
                b._isActive = false
                UpdateButtonStyle(b)
            end
            s._isActive = true
            UpdateButtonStyle(s)
            local value = s._value
            AC.Settings[key] = value
            SendSettingToServer(key, value)
            if SetPlayerSetting then SetPlayerSetting(LocalPlayer(), key, value) end
            if callback then callback(value) end
        end
        table.insert(buttons, btn)
    end
    pnl._buttons = buttons
    pnl._key = key
    pnl.SetValue = function(s, value)
        for _, btn in ipairs(s._buttons) do
            btn._isActive = (btn._value == value)
            if btn._isActive then
                btn._textLabel:SetTextColor(Color(100, 255, 100))
            else
                btn._textLabel:SetTextColor(Color(255, 100, 100))
            end
        end
    end
    return pnl
end
function PANEL:BuildMainTab()
    local scroll = vgui.Create("DScrollPanel")
    self.Sheet:AddSheet(L:Get("menu_main"), scroll, "icon16/cog.png")
    local panel = vgui.Create("DPanel", scroll)
    panel:Dock(TOP)
    panel:SetTall(950)
    panel.Paint = function() end
    self:CreateSection(panel, L:Get("menu_language"))
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
    langLbl:SetText(L:Get("menu_language") .. ":")
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
        local available = _L:GetAvailable()
        local current = _L:GetLang()
        local LANG_NAMES = {
            ru = "Русский",
            en = "English",
            es = "Español",
            de = "Deutsch",
            fr = "Français",
            zh = "中文",
            ja = "日本語",
            ko = "한국어",
            pt = "Português",
            it = "Italiano",
            pl = "Polski",
            tr = "Türkçe",
            uk = "Українська",
            cs = "Čeština",
            sv = "Svenska",
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
        if lang and lang ~= _L:GetLang() then
            local savedValues = {}
            for key, entry in pairs(self.InputFields) do
                if IsValid(entry) then
                    savedValues[key] = entry:GetText()
                end
            end
            _L:SetLang(lang)
            if AC.Settings then
                AC.Settings.locale = lang
                AI_SaveSettings()
            end
            if SERVER then
                if SetPlayerSetting then
                    SetPlayerSetting(LocalPlayer(), "locale", lang)
                end
                net.Start("AI_Locale_Sync")
                net.WriteString(lang)
                net.SendToServer()
            end
            if IsValid(self.Sheet) then
                self.Sheet:Clear()
            end
            self:BuildMainTab()
            self:BuildLLMTab()
            self:BuildTTSTab()
            if not IS_SOLO then
                self:BuildBotTab()
                self:BuildCombatTab()
            end
            self:BuildAppearanceTab()
            self:BuildInfoTab()
            self:BuildPromptTab()
            self:BuildWorkflowTab()
            self:RefreshValues()
            timer.Simple(0.15, function()
                if not IsValid(self) then return end
                for key, value in pairs(savedValues) do
                    local entry = self.InputFields[key]
                    if IsValid(entry) then
                        entry._updatingFromServer = true
                        entry:SetText(value)
                        entry._lastText = value
                        timer.Simple(0.1, function()
                            if IsValid(entry) then
                                entry._updatingFromServer = false
                            end
                        end)
                    end
                end
            end)
            UpdateLanguageCombo()
            chat.AddText(Color(100, 200, 255), "[AI] " .. L:Get("console_locale_loaded"):format(lang))
        end
    end
    self.LangCombo = langCombo
    self.UpdateLanguageCombo = UpdateLanguageCombo
    self:CreateSection(panel, L:Get("menu_network"))
    self:CreateTextEntry(panel, L:Get("menu_llm_ip"), L:Get("tooltip_llm_ip"),
        AC.Settings.llm_ip or "127.0.0.1",
        function(text)
            local ok, err = AI_Utils.ValidateIP(text)
            if not ok then
                LocalPlayer():ChatPrint("[" .. L:Get("ai_prefix") .. "] " .. L:Get("settings_invalid_ip"))
                return
            end
            AC.Settings.llm_ip = text
            SendSettingToServer("llm_ip", text)
            if SetPlayerSetting then
                SetPlayerSetting(LocalPlayer(), "llm_ip", text)
            end
        end, "llm_ip")
    self:CreateTextEntry(panel, L:Get("menu_llm_port"), L:Get("tooltip_llm_port"),
        tostring(AC.Settings.llm_port or 1234),
        function(text)
            local port = tonumber(text)
            local ok, portNum = AI_Utils.ValidatePort(port)
            if not ok then
                LocalPlayer():ChatPrint("[" .. L:Get("ai_prefix") .. "] " .. L:Get("settings_invalid_port"))
                return
            end
            AC.Settings.llm_port = portNum
            SendSettingToServer("llm_port", portNum)
            if SetPlayerSetting then
                SetPlayerSetting(LocalPlayer(), "llm_port", portNum)
            end
        end, "llm_port")
    self:CreateTextEntry(panel, L:Get("menu_llm_model"), L:Get("tooltip_llm_model"),
        AC.Settings.llm_model or "local-model",
        function(text)
            AC.Settings.llm_model = text
            SendSettingToServer("llm_model", text)
            if SetPlayerSetting then
                SetPlayerSetting(LocalPlayer(), "llm_model", text)
            end
        end, "llm_model")
    self:CreateTextEntry(panel, L:Get("menu_tts_ip"), L:Get("tooltip_tts_ip"),
        AC.Settings.comfyui_ip or "127.0.0.1",
        function(text)
            local ok, err = AI_Utils.ValidateIP(text)
            if not ok then
                LocalPlayer():ChatPrint("[" .. L:Get("ai_prefix") .. "] " .. L:Get("settings_invalid_ip"))
                return
            end
            AC.Settings.comfyui_ip = text
            SendSettingToServer("comfyui_ip", text)
            if SetPlayerSetting then
                SetPlayerSetting(LocalPlayer(), "comfyui_ip", text)
            end
        end, "comfyui_ip")
    self:CreateTextEntry(panel, L:Get("menu_tts_port"), L:Get("tooltip_tts_port"),
        tostring(AC.Settings.comfyui_port or 8188),
        function(text)
            local port = tonumber(text)
            local ok, portNum = AI_Utils.ValidatePort(port)
            if not ok then
                LocalPlayer():ChatPrint("[" .. L:Get("ai_prefix") .. "] " .. L:Get("settings_invalid_port"))
                return
            end
            AC.Settings.comfyui_port = portNum
            SendSettingToServer("comfyui_port", portNum)
            if SetPlayerSetting then
                SetPlayerSetting(LocalPlayer(), "comfyui_port", portNum)
            end
        end, "comfyui_port")
    self:CreateTextEntry(panel, L:Get("menu_llm_timeout"), L:Get("tooltip_llm_timeout"),
        tostring(AC.Settings.llm_timeout or 60),
        function(text)
            local ply = LocalPlayer()
            if IsValid(ply) then
                local val = tonumber(text)
                if val and val >= 5 and val <= 300 then
                    AC.Settings.llm_timeout = val
                    SendSettingToServer("llm_timeout", val)
                    if SetPlayerSetting then
                        SetPlayerSetting(ply, "llm_timeout", val)
                    end
                else
                    ply:ChatPrint("[" .. L:Get("ai_prefix") .. "] " .. L:Get("settings_timeout_invalid"))
                end
            end
        end, "llm_timeout")
    self:CreateTextEntry(panel, L:Get("menu_tts_timeout"), L:Get("tooltip_tts_timeout"),
        tostring(AC.Settings.tts_timeout or 120),
        function(text)
            local ply = LocalPlayer()
            if IsValid(ply) then
                local val = tonumber(text)
                if val and val >= 5 and val <= 300 then
                    AC.Settings.tts_timeout = val
                    SendSettingToServer("tts_timeout", val)
                    if SetPlayerSetting then
                        SetPlayerSetting(ply, "tts_timeout", val)
                    end
                else
                    ply:ChatPrint("[" .. L:Get("ai_prefix") .. "] " .. L:Get("settings_timeout_invalid"))
                end
            end
        end, "tts_timeout")
    self:CreateSection(panel, L:Get("menu_modes"))
    self:CreateModeToggle(panel, L:Get("menu_llm_mode"), L:Get("tooltip_llm_mode"),
        {
            { id = "local", name = L:Get("llm_local"), desc = L:Get("llm_local_desc") },
            { id = "cloud", name = L:Get("llm_cloud"), desc = L:Get("llm_cloud_desc") },
            { id = "disabled", name = L:Get("llm_disabled_status"), desc = L:Get("llm_disabled_desc") }
        },
        function(value)
            if value == "local" then
                AC.Settings.llm_enabled = true
                AC.Settings.llm_mode = "local"
                SendSettingToServer("llm_mode", "local")
                SendSettingToServer("llm_enabled", true)
                if SetPlayerSetting then
                    SetPlayerSetting(LocalPlayer(), "llm_mode", "local")
                    SetPlayerSetting(LocalPlayer(), "llm_enabled", true)
                end
                _G.AI_Companion_LLM_Enabled = true
                LocalPlayer():ChatPrint("[" .. L:Get("ai_prefix") .. "] " .. L:Get("llm_local"))
            elseif value == "cloud" then
                AC.Settings.llm_enabled = true
                AC.Settings.llm_mode = "cloud"
                SendSettingToServer("llm_mode", "cloud")
                SendSettingToServer("llm_enabled", true)
                if SetPlayerSetting then
                    SetPlayerSetting(LocalPlayer(), "llm_mode", "cloud")
                    SetPlayerSetting(LocalPlayer(), "llm_enabled", true)
                end
                _G.AI_Companion_LLM_Enabled = true
                LocalPlayer():ChatPrint("[" .. L:Get("ai_prefix") .. "] " .. L:Get("llm_cloud"))
            else
                AC.Settings.llm_enabled = false
                AC.Settings.llm_mode = "disabled"
                SendSettingToServer("llm_mode", "disabled")
                SendSettingToServer("llm_enabled", false)
                if SetPlayerSetting then
                    SetPlayerSetting(LocalPlayer(), "llm_mode", "disabled")
                    SetPlayerSetting(LocalPlayer(), "llm_enabled", false)
                end
                _G.AI_Companion_LLM_Enabled = false
                LocalPlayer():ChatPrint("[" .. L:Get("ai_prefix") .. "] " .. L:Get("llm_disabled_status"))
            end
            self:RefreshValues()
        end,
        "llm_mode", AC.Settings.llm_mode or "local")
    self:CreateModeToggle(panel, L:Get("menu_tts_mode"), L:Get("tooltip_tts_mode"),
        {
            { id = "local", name = L:Get("tts_local"), desc = L:Get("tts_local_desc") },
            { id = "cloud", name = L:Get("tts_cloud"), desc = L:Get("tts_cloud_desc") },
            { id = "disabled", name = L:Get("tts_disabled"), desc = L:Get("tts_disabled_desc") }
        },
        function(value)
            if value == "local" then
                AC.Settings.tts_enabled = true
                AC.Settings.tts_mode = "local"
                SendSettingToServer("tts_mode", "local")
                SendSettingToServer("tts_enabled", true)
                if SetPlayerSetting then
                    SetPlayerSetting(LocalPlayer(), "tts_mode", "local")
                    SetPlayerSetting(LocalPlayer(), "tts_enabled", true)
                end
                _G.AI_Companion_TTS_Enabled = true
                LocalPlayer():ChatPrint("[" .. L:Get("ai_prefix") .. "] " .. L:Get("tts_local"))
            elseif value == "cloud" then
                AC.Settings.tts_enabled = true
                AC.Settings.tts_mode = "cloud"
                SendSettingToServer("tts_mode", "cloud")
                SendSettingToServer("tts_enabled", true)
                if SetPlayerSetting then
                    SetPlayerSetting(LocalPlayer(), "tts_mode", "cloud")
                    SetPlayerSetting(LocalPlayer(), "tts_enabled", true)
                end
                _G.AI_Companion_TTS_Enabled = true
                LocalPlayer():ChatPrint("[" .. L:Get("ai_prefix") .. "] " .. L:Get("tts_cloud"))
            else
                AC.Settings.tts_enabled = false
                AC.Settings.tts_mode = "disabled"
                SendSettingToServer("tts_mode", "disabled")
                SendSettingToServer("tts_enabled", false)
                if SetPlayerSetting then
                    SetPlayerSetting(LocalPlayer(), "tts_mode", "disabled")
                    SetPlayerSetting(LocalPlayer(), "tts_enabled", false)
                end
                _G.AI_Companion_TTS_Enabled = false
                LocalPlayer():ChatPrint("[" .. L:Get("ai_prefix") .. "] " .. L:Get("tts_disabled"))
            end
            self:RefreshValues()
        end,
        "tts_mode", AC.Settings.tts_mode or "local")
    self:CreateToggle(panel, L:Get("menu_tts_personal"), L:Get("tooltip_tts_personal"),
        AC.Settings.tts_personal or true,
        function(val)
            AC.Settings.tts_personal = val
            SendSettingToServer("tts_personal", val)
            if SetPlayerSetting then
                SetPlayerSetting(LocalPlayer(), "tts_personal", val)
            end
            local state = val and L:Get("mode_on") or L:Get("mode_off")
            LocalPlayer():ChatPrint("[" .. L:Get("ai_prefix") .. "] " .. L:Get("tts_personal"):format(state))
        end, "tts_personal")
    self:CreateToggle(panel, L:Get("menu_debug"), L:Get("tooltip_debug"),
        AC.Settings.debug_mode or false,
        function(val)
            AC.Settings.debug_mode = val
            SendSettingToServer("debug_mode", val)
            if SetPlayerSetting then
                SetPlayerSetting(LocalPlayer(), "debug_mode", val)
            end
            if AI_CONFIG then
                AI_CONFIG.DEBUG_MODE = val
            end
            local state = val and L:Get("mode_on") or L:Get("mode_off")
            print("[AI] " .. L:Get("settings_debug"):format(state))
            LocalPlayer():ChatPrint("[" .. L:Get("ai_prefix") .. "] " .. L:Get("settings_debug"):format(state))
        end, "debug_mode")
    self:CreateSection(panel, L:Get("menu_tools"))
    self:CreateButton(panel, L:Get("menu_ping"), L:Get("tooltip_ping"),
        function()
            local ply = LocalPlayer()
            if IsValid(ply) then
                ply:ConCommand("ai_ping_servers")
            end
        end)
    self:CreateButton(panel, L:Get("menu_show_models"), L:Get("tooltip_show_models"),
        function()
            local models = player_manager.AllValidModels()
            print("")
            print("═══════════════════════════════════════════════════════")
            print("        " .. L:Get("menu_show_models"))
            print("═══════════════════════════════════════════════════════")
            print("")
            print(string.format("%-35s | %s", L:Get("model_name"), L:Get("model_path")))
            print(string.rep("─", 80))
            if not models or next(models) == nil then
                print("  " .. L:Get("no_models_found"))
            else
                local sorted = {}
                for name, path in pairs(models) do
                    table.insert(sorted, {name = name, path = path})
                end
                table.sort(sorted, function(a, b) return a.name < b.name end)
                for _, entry in ipairs(sorted) do
                    print(string.format("%-35s | %s", entry.name, entry.path))
                end
                print("")
                print(string.rep("─", 80))
                print(string.format("  " .. L:Get("total_models"), table.Count(models)))
            end
            print("")
            local ply = LocalPlayer()
            if IsValid(ply) then
                ply:ChatPrint("[" .. L:Get("ai_prefix") .. "] " .. L:Get("models_printed_to_console"))
            end
        end)
    self:CreateButton(panel, L:Get("menu_show_status"), L:Get("tooltip_show_status"),
        function()
            local ply = LocalPlayer()
            if IsValid(ply) then
                ply:ConCommand("ai_companion_status")
            end
        end)
    self:CreateButton(panel, L:Get("menu_reset"), L:Get("tooltip_reset"),
        function()
            Derma_Query(
                L:Get("dialog_reset_text"),
                L:Get("dialog_replace_title"),
                L:Get("dialog_yes"),
                function()
                    local ply = LocalPlayer()
                    if IsValid(ply) then
                        ply:ConCommand("ai_reset_settings")
                        timer.Simple(0.5, function()
                            if IsValid(self) then
                                self:RefreshValues()
                                ply:ChatPrint("[" .. L:Get("ai_prefix") .. "] " .. L:Get("settings_reset"))
                            end
                        end)
                    end
                end,
                L:Get("dialog_no"),
                function() end
            )
        end)
    if LocalPlayer():IsAdmin() then
        self:CreateSection(panel, L:Get("menu_admin"))
        self:CreateButton(panel, L:Get("menu_sync_global"), L:Get("tooltip_sync_global"),
            function()
                Derma_Query(
                    L:Get("sync_confirm_text"),
                    L:Get("dialog_replace_title"),
                    L:Get("dialog_yes"),
                    function()
                        LocalPlayer():ConCommand("ai_sync_global")
                    end,
                    L:Get("dialog_no"),
                    function() end
                )
            end)
        self.AutoSyncButton = self:CreateButton(panel, 
            L:Get("menu_auto_sync") .. ": " .. ((AC.Settings.auto_sync_global ~= false) and L:Get("mode_on") or L:Get("mode_off")),
            L:Get("tooltip_auto_sync"),
            function()
                LocalPlayer():ConCommand("ai_auto_sync")
                timer.Simple(0.3, function()
                    if IsValid(self) and IsValid(self.AutoSyncButton) then
                        local status = (AC.Settings.auto_sync_global ~= false) and L:Get("mode_on") or L:Get("mode_off")
                        self.AutoSyncButton:SetText(L:Get("menu_auto_sync") .. ": " .. status)
                    end
                end)
            end)
    end
    self:CreateSection(panel, L:Get("menu_status"))
    local statusPanel = vgui.Create("DPanel", panel)
    statusPanel:Dock(TOP)
    statusPanel:DockMargin(8, 4, 8, 8)
    statusPanel:SetTall(140)
    statusPanel.Paint = function(s, w, h)
        surface.SetDrawColor(25, 25, 35, 220)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(60, 60, 80, 100)
        surface.DrawOutlinedRect(0, 0, w, h)
        local llmStatus = ""
        if AC.Settings.llm_enabled == false then
            llmStatus = L:Get("llm_disabled_status")
        elseif AC.Settings.llm_mode == "cloud" then
            llmStatus = L:Get("llm_cloud")
        else
            llmStatus = L:Get("llm_local")
        end
        local ttsStatus = ""
        if AC.Settings.tts_enabled == false then
            ttsStatus = L:Get("tts_disabled")
        elseif AC.Settings.tts_mode == "cloud" then
            ttsStatus = L:Get("tts_cloud")
        else
            ttsStatus = L:Get("tts_local")
        end
        local personalStatus = AC.Settings.tts_personal and L:Get("mode_on") or L:Get("mode_off")
        local debugStatus = AC.Settings.debug_mode and L:Get("mode_on") or L:Get("mode_off")
        local langStatus = _L:GetLang() == "ru" and "Русский" or
                          _L:GetLang() == "en" and "English" or
                          _L:GetLang()
        draw.SimpleText(L:Get("menu_llm_status"):format(llmStatus), "DermaDefault", 12, 12, Color(200, 200, 200))
        draw.SimpleText(L:Get("menu_tts_status"):format(ttsStatus, personalStatus), "DermaDefault", 12, 34, Color(200, 200, 200))
        draw.SimpleText(L:Get("menu_debug_status"):format(debugStatus), "DermaDefault", 12, 56, Color(200, 200, 200))
        draw.SimpleText(L:Get("menu_language") .. ": " .. langStatus, "DermaDefault", 12, 78, Color(200, 200, 200))
        draw.SimpleText("LLM Timeout: " .. tostring(AC.Settings.llm_timeout or 60) .. "s | TTS Timeout: " .. tostring(AC.Settings.tts_timeout or 120) .. "s", "DermaDefault", 12, 100, Color(180, 180, 200))
    end
    statusPanel.Think = function(s)
        s:InvalidateLayout()
    end
end
function PANEL:BuildLLMTab()
    local scroll = vgui.Create("DScrollPanel")
    self.Sheet:AddSheet(L:Get("menu_llm"), scroll, "icon16/world.png")
    local panel = vgui.Create("DPanel", scroll)
    panel:Dock(TOP)
    panel:SetTall(500)
    panel.Paint = function() end
    local warn = vgui.Create("DLabel", panel)
    warn:SetText(" " .. L:Get("llm_local_hint"))
    warn:Dock(TOP)
    warn:DockMargin(8, 4, 8, 4)
    warn:SetTall(24)
    warn:SetTextColor(Color(255, 200, 100))
    warn:SetFont("DermaDefaultBold")
    self:CreateSection(panel, L:Get("menu_cloud_llm"))
    local providers = GetAvailableLLMProviders and GetAvailableLLMProviders() or {
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
    providerLbl:SetText(L:Get("menu_provider"))
    providerLbl:Dock(LEFT)
    providerLbl:DockMargin(8, 0, 8, 0)
    providerLbl:SetWide(80)
    providerLbl:SetTextColor(Color(220,220,220))
    local providerCombo = vgui.Create("DComboBox", providerPanel)
    providerCombo:Dock(FILL)
    providerCombo:DockMargin(0, 2, 8, 2)
    local currentProvider = AC.Settings.llm_provider or "openai"
    for _, p in ipairs(providers) do
        providerCombo:AddChoice(p.name, p)
        if p.id == currentProvider then
            providerCombo:SetText(p.name)
        end
    end
    providerCombo.OnSelect = function(combo, index, value, data)
        local provider = data
        if not provider then return end
        AC.Settings.llm_provider = provider.id
        SendSettingToServer("llm_provider", provider.id)
        if SetPlayerSetting then
            SetPlayerSetting(LocalPlayer(), "llm_provider", provider.id)
        end
        self:RefreshValues()
    end
    self:CreateTextEntry(panel, L:Get("menu_api_key"), L:Get("tooltip_llm_api_key"),
        AC.Settings.llm_api_key or "",
        function(text)
            AC.Settings.llm_api_key = text
            SendSettingToServer("llm_api_key", text)
            if SetPlayerSetting then
                SetPlayerSetting(LocalPlayer(), "llm_api_key", text)
            end
        end, "llm_api_key")
    self:CreateTextEntry(panel, L:Get("menu_cloud_model"), L:Get("tooltip_llm_cloud_model"),
        AC.Settings.llm_cloud_model or "",
        function(text)
            AC.Settings.llm_cloud_model = text
            SendSettingToServer("llm_cloud_model", text)
            if SetPlayerSetting then
                SetPlayerSetting(LocalPlayer(), "llm_cloud_model", text)
            end
        end, "llm_cloud_model")
    self:CreateTextEntry(panel, L:Get("menu_endpoint"), L:Get("tooltip_llm_endpoint"),
        AC.Settings.llm_endpoint or "",
        function(text)
            AC.Settings.llm_endpoint = text
            SendSettingToServer("llm_endpoint", text)
            if SetPlayerSetting then
                SetPlayerSetting(LocalPlayer(), "llm_endpoint", text)
            end
        end, "llm_endpoint")
    self:CreateButton(panel, L:Get("menu_test_connection"), L:Get("tooltip_test_llm"),
        function()
            local ply = LocalPlayer()
            if IsValid(ply) then
                ply:ConCommand("ai_test_llm")
                chat.AddText(Color(100, 200, 255), "[AI] " .. L:Get("llm_testing"))
                print("[AI MENU] " .. L:Get("llm_testing"))
            end
        end)
end
function PANEL:BuildTTSTab()
    local scroll = vgui.Create("DScrollPanel")
    self.Sheet:AddSheet(L:Get("menu_tts"), scroll, "icon16/sound.png")
    local panel = vgui.Create("DPanel", scroll)
    panel:Dock(TOP)
    panel:SetTall(750)
    panel.Paint = function() end
    local warn = vgui.Create("DLabel", panel)
    warn:SetText(" " .. L:Get("tts_local_hint"))
    warn:Dock(TOP)
    warn:DockMargin(8, 4, 8, 4)
    warn:SetTall(24)
    warn:SetTextColor(Color(255, 200, 100))
    warn:SetFont("DermaDefaultBold")
    self:CreateSection(panel, L:Get("menu_cloud_tts"))
    local providers = GetAvailableTTSProviders and GetAvailableTTSProviders() or {
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
    providerLbl:SetText(L:Get("menu_provider"))
    providerLbl:Dock(LEFT)
    providerLbl:DockMargin(8, 0, 8, 0)
    providerLbl:SetWide(80)
    providerLbl:SetTextColor(Color(220,220,220))
    local providerCombo = vgui.Create("DComboBox", providerPanel)
    providerCombo:Dock(FILL)
    providerCombo:DockMargin(0, 2, 8, 2)
    local currentProvider = AC.Settings.tts_provider or "elevenlabs"
    for _, p in ipairs(providers) do
        providerCombo:AddChoice(p.name, p)
        if p.id == currentProvider then
            providerCombo:SetText(p.name)
        end
    end
    providerCombo.OnSelect = function(combo, index, value, data)
        local provider = data
        if not provider then return end
        AC.Settings.tts_provider = provider.id
        SendSettingToServer("tts_provider", provider.id)
        if SetPlayerSetting then
            SetPlayerSetting(LocalPlayer(), "tts_provider", provider.id)
        end
        self:RefreshValues()
    end
    self:CreateSection(panel, L:Get("menu_common_settings"))
    self:CreateTextEntry(panel, L:Get("menu_api_key"), L:Get("tooltip_tts_api_key"),
        AC.Settings.tts_api_key or "",
        function(text)
            AC.Settings.tts_api_key = text
            SendSettingToServer("tts_api_key", text)
            if SetPlayerSetting then
                SetPlayerSetting(LocalPlayer(), "tts_api_key", text)
            end
        end, "tts_api_key")
    self:CreateTextEntry(panel, L:Get("menu_endpoint"), L:Get("tooltip_tts_endpoint"),
        AC.Settings.tts_endpoint or "",
        function(text)
            AC.Settings.tts_endpoint = text
            SendSettingToServer("tts_endpoint", text)
            if SetPlayerSetting then
                SetPlayerSetting(LocalPlayer(), "tts_endpoint", text)
            end
        end, "tts_endpoint")
    self:CreateSection(panel, "ElevenLabs")
    self:CreateTextEntry(panel, L:Get("menu_voice"), L:Get("tooltip_elevenlabs_voice"),
        AC.Settings.tts_voice or "",
        function(text)
            AC.Settings.tts_voice = text
            SendSettingToServer("tts_voice", text)
            if SetPlayerSetting then
                SetPlayerSetting(LocalPlayer(), "tts_voice", text)
            end
        end, "tts_voice")
    self:CreateSection(panel, "Google Cloud TTS")
    self:CreateTextEntry(panel, L:Get("menu_language"), L:Get("tooltip_google_lang"),
        AC.Settings.tts_language or "",
        function(text)
            AC.Settings.tts_language = text
            SendSettingToServer("tts_language", text)
            if SetPlayerSetting then
                SetPlayerSetting(LocalPlayer(), "tts_language", text)
            end
        end, "tts_language")
    self:CreateTextEntry(panel, L:Get("menu_voice"), L:Get("tooltip_google_voice"),
        AC.Settings.tts_voice or "",
        function(text)
            AC.Settings.tts_voice = text
            SendSettingToServer("tts_voice", text)
            if SetPlayerSetting then
                SetPlayerSetting(LocalPlayer(), "tts_voice", text)
            end
        end, "tts_voice")
    self:CreateSection(panel, "Yandex SpeechKit")
    self:CreateTextEntry(panel, L:Get("menu_yandex_folder"), L:Get("tooltip_yandex_folder"),
        AC.Settings.yandex_folder_id or "",
        function(text)
            AC.Settings.yandex_folder_id = text
            SendSettingToServer("yandex_folder_id", text)
            if SetPlayerSetting then
                SetPlayerSetting(LocalPlayer(), "yandex_folder_id", text)
            end
        end, "yandex_folder_id")
    self:CreateTextEntry(panel, L:Get("menu_yandex_voice"), L:Get("tooltip_yandex_voice"),
        AC.Settings.yandex_voice or "oksana",
        function(text)
            AC.Settings.yandex_voice = text
            SendSettingToServer("yandex_voice", text)
            if SetPlayerSetting then
                SetPlayerSetting(LocalPlayer(), "yandex_voice", text)
            end
        end, "yandex_voice")
    self:CreateTextEntry(panel, L:Get("menu_yandex_lang"), L:Get("tooltip_yandex_lang"),
        AC.Settings.yandex_lang or "ru-RU",
        function(text)
            AC.Settings.yandex_lang = text
            SendSettingToServer("yandex_lang", text)
            if SetPlayerSetting then
                SetPlayerSetting(LocalPlayer(), "yandex_lang", text)
            end
        end, "yandex_lang")
    self:CreateSection(panel, "VK Cloud Voice")
    self:CreateTextEntry(panel, L:Get("menu_vk_voice"), L:Get("tooltip_vk_voice"),
        AC.Settings.vk_voice or "katherine",
        function(text)
            AC.Settings.vk_voice = text
            SendSettingToServer("vk_voice", text)
            if SetPlayerSetting then
                SetPlayerSetting(LocalPlayer(), "vk_voice", text)
            end
        end, "vk_voice")
    self:CreateTextEntry(panel, L:Get("menu_vk_tempo"), L:Get("tooltip_vk_tempo"),
        tostring(AC.Settings.vk_tempo or 1.0),
        function(text)
            local tempo = tonumber(text)
            if tempo and tempo >= 0.75 and tempo <= 1.75 then
                AC.Settings.vk_tempo = tempo
                SendSettingToServer("vk_tempo", tempo)
                if SetPlayerSetting then
                    SetPlayerSetting(LocalPlayer(), "vk_tempo", tempo)
                end
            else
                LocalPlayer():ChatPrint("[AI] " .. L:Get("vk_tempo_invalid"))
            end
        end, "vk_tempo")
    self:CreateSection(panel, L:Get("menu_tools"))
    self:CreateButton(panel, L:Get("menu_test_tts"), L:Get("tooltip_test_tts"),
        function()
            local ply = LocalPlayer()
            if IsValid(ply) then
                ply:ConCommand("ai_test_tts")
                chat.AddText(Color(100, 200, 255), "[AI] " .. L:Get("tts_testing"))
                print("[AI MENU] " .. L:Get("tts_testing"))
            end
        end)
end
function PANEL:BuildBotTab()
    if IS_SOLO then return end
    local scroll = vgui.Create("DScrollPanel")
    self.Sheet:AddSheet(L:Get("menu_bot"), scroll, "icon16/user.png")
    local panel = vgui.Create("DPanel", scroll)
    panel:Dock(TOP)
    panel:SetTall(500)
    panel.Paint = function() end
    self:CreateSection(panel, L:Get("menu_bot_creation"))
    self:CreateButton(panel, L:Get("menu_create"), L:Get("tooltip_create"),
        function()
            local ply = LocalPlayer()
            if not IsValid(ply) then return end
            if HasCompanion(ply) then
                local bot = GetCompanion(ply)
                local name = IsValid(bot) and bot:Nick() or L:Get("unknown")
                Derma_Query(
                    L:Get("dialog_replace_text"):format(name),
                    L:Get("dialog_replace_title"),
                    L:Get("dialog_yes"),
                    function()
                        self:RunCommand("ai_companion_remove")
                        timer.Simple(0.5, function()
                            self:RunCommand("ai_companion_create")
                        end)
                    end,
                    L:Get("dialog_no"),
                    function() end
                )
            else
                self:RunCommand("ai_companion_create")
            end
        end)
    self:CreateButton(panel, L:Get("menu_remove"), L:Get("tooltip_remove"),
        function()
            local ply = LocalPlayer()
            if not IsValid(ply) then return end
            if not HasCompanion(ply) then
                ply:ChatPrint("[" .. L:Get("ai_prefix") .. "] " .. L:Get("bot_not_found"))
                return
            end
            Derma_Query(
                L:Get("dialog_remove_text"),
                L:Get("dialog_replace_title"),
                L:Get("dialog_yes"),
                function()
                    self:RunCommand("ai_companion_remove")
                end,
                L:Get("dialog_no"),
                function() end
            )
        end)
    self:CreateButton(panel, L:Get("menu_replace"), L:Get("tooltip_replace"),
        function()
            local ply = LocalPlayer()
            if not IsValid(ply) then return end
            if not HasCompanion(ply) then
                ply:ChatPrint("[" .. L:Get("ai_prefix") .. "] " .. L:Get("bot_not_found"))
                return
            end
            Derma_Query(
                L:Get("dialog_replace_text"):format(GetCompanion(ply):Nick() or L:Get("unknown")),
                L:Get("dialog_replace_title"),
                L:Get("dialog_yes"),
                function()
                    self:RunCommand("ai_companion_replace")
                end,
                L:Get("dialog_no"),
                function() end
            )
        end)
    self:CreateSection(panel, L:Get("menu_bot_settings"))
    self:CreateTextEntry(panel, L:Get("menu_name"), L:Get("tooltip_nick"),
        AC.Settings.companion_nick or "AI_Companion",
        function(text)
            local ply = LocalPlayer()
            if not IsValid(ply) then return end
            text = string.Trim(text)
            if text == "" then
                ply:ChatPrint("[AI] " .. L:Get("settings_nick_empty"))
                return
            end
            if #text > (AI.Config.UI.MaxNickLength or 32) then
                text = string.sub(text, 1, AI.Config.UI.MaxNickLength or 32)
            end
            if AC.Settings then AC.Settings.companion_nick = text end
            SendSettingToServer("companion_nick", text)
            if SetPlayerSetting then
                SetPlayerSetting(ply, "companion_nick", text)
            end
            local bot = GetCompanion(ply)
            if IsValid(bot) then
                pcall(function() bot:SetName(text) end)
                pcall(function() bot:SetNick(text) end)
            end
        end, "companion_nick")
    self:CreateTextEntry(panel, L:Get("menu_model"), L:Get("tooltip_model"),
        AC.Settings.model_path or "models/player/urban.mdl",
        function(text)
            local ply = LocalPlayer()
            if IsValid(ply) and SetPlayerSetting then
                SetPlayerSetting(ply, "model_path", text)
                local bot = GetCompanion(ply)
                if IsValid(bot) then
                    pcall(function() bot:SetModel(text) end)
                end
            end
        end, "model_path")
    self:CreateSection(panel, L:Get("menu_bot_control"))
    self:CreateButton(panel, L:Get("menu_follow"), L:Get("tooltip_follow"),
        function()
            LocalPlayer():ConCommand("say !companion follow")
        end)
    self:CreateButton(panel, L:Get("menu_point"), L:Get("tooltip_point"),
        function()
            LocalPlayer():ConCommand("say !companion point")
        end)
    self:CreateButton(panel, L:Get("menu_stop"), L:Get("tooltip_stop"),
        function()
            LocalPlayer():ConCommand("say !companion stop")
        end)
    self:CreateButton(panel, L:Get("menu_attack"), L:Get("tooltip_attack"),
        function()
            LocalPlayer():ConCommand("say !companion attack")
        end)
    self:CreateButton(panel, L:Get("menu_sit"), L:Get("tooltip_sit"),
        function()
            LocalPlayer():ConCommand("say !companion sit")
        end)
    self:CreateButton(panel, L:Get("menu_standup"), L:Get("tooltip_standup"),
        function()
            LocalPlayer():ConCommand("say !companion standup")
        end)
    self:CreateButton(panel, L:Get("menu_teleport"), L:Get("tooltip_teleport"),
        function()
            self:RunCommand("ai_companion_teleport")
        end)
end
function PANEL:BuildCombatTab()
    if IS_SOLO then return end
    local scroll = vgui.Create("DScrollPanel")
    self.Sheet:AddSheet(L:Get("menu_combat"), scroll, "icon16/gun.png")
    local panel = vgui.Create("DPanel", scroll)
    panel:Dock(TOP)
    panel:SetTall(500)
    panel.Paint = function() end
    self:CreateSection(panel, L:Get("menu_weapons"))
    self:CreateTextEntry(panel, L:Get("menu_combat_weapon"), L:Get("tooltip_combat_weapon"),
        AC.Settings.combat_weapon or "weapon_smg1",
        function(text)
            local ply = LocalPlayer()
            if not IsValid(ply) then return end
            text = string.Trim(text)
            if text == "" then
                ply:ChatPrint("[AI] " .. L:Get("settings_weapon_empty"))
                return
            end
            if not weapons.Get(text) then
                ply:ChatPrint("[AI] " .. L:Get("settings_weapon_invalid"):format(text))
                return
            end
            if AC.Settings then AC.Settings.combat_weapon = text end
            SendSettingToServer("combat_weapon", text)
            if SetPlayerSetting then
                SetPlayerSetting(ply, "combat_weapon", text)
            end
        end, "combat_weapon")
    self:CreateTextEntry(panel, L:Get("menu_melee_weapon"), L:Get("tooltip_melee_weapon"),
        AC.Settings.melee_weapon or "weapon_crowbar",
        function(text)
            local ply = LocalPlayer()
            if not IsValid(ply) then return end
            text = string.Trim(text)
            if text == "" then
                ply:ChatPrint("[AI] " .. L:Get("settings_weapon_empty"))
                return
            end
            if not weapons.Get(text) then
                ply:ChatPrint("[AI] " .. L:Get("settings_weapon_invalid"):format(text))
                return
            end
            if AC.Settings then AC.Settings.melee_weapon = text end
            SendSettingToServer("melee_weapon", text)
            if SetPlayerSetting then
                SetPlayerSetting(ply, "melee_weapon", text)
            end
        end, "melee_weapon")
    self:CreateTextEntry(panel, L:Get("menu_idle_weapon"), L:Get("tooltip_idle_weapon"),
        AC.Settings.idle_weapon or "weapon_physgun",
        function(text)
            local ply = LocalPlayer()
            if not IsValid(ply) then return end
            text = string.Trim(text)
            if text == "" then
                ply:ChatPrint("[AI] " .. L:Get("settings_weapon_empty"))
                return
            end
            if not weapons.Get(text) then
                ply:ChatPrint("[AI] " .. L:Get("settings_weapon_invalid"):format(text))
                return
            end
            if AC.Settings then AC.Settings.idle_weapon = text end
            SendSettingToServer("idle_weapon", text)
            if SetPlayerSetting then
                SetPlayerSetting(ply, "idle_weapon", text)
            end
        end, "idle_weapon")
    self:CreateSection(panel, L:Get("menu_behavior"))
    self:CreateToggle(panel, L:Get("menu_stealth"), L:Get("tooltip_stealth"),
        AC.Settings.stealth_mode or false,
        function(val)
            local ply = LocalPlayer()
            if IsValid(ply) then
                local state = val and L:Get("mode_on") or L:Get("mode_off")
                ply:ChatPrint("[" .. L:Get("ai_prefix") .. "] " .. L:Get("mode_stealth"):format(state))
            end
        end, "stealth_mode")
    self:CreateToggle(panel, L:Get("menu_pacifist"), L:Get("tooltip_pacifist"),
        AC.Settings.pacifist_mode or false,
        function(val)
            local ply = LocalPlayer()
            if IsValid(ply) then
                local state = val and L:Get("mode_on") or L:Get("mode_off")
                ply:ChatPrint("[" .. L:Get("ai_prefix") .. "] " .. L:Get("mode_pacifist"):format(state))
            end
        end, "pacifist_mode")
    self:CreateToggle(panel, L:Get("menu_aggressive"), L:Get("tooltip_aggressive"),
        AC.Settings.aggressive_mode or false,
        function(val)
            local ply = LocalPlayer()
            if IsValid(ply) then
                local state = val and L:Get("mode_on") or L:Get("mode_off")
                ply:ChatPrint("[" .. L:Get("ai_prefix") .. "] " .. L:Get("mode_aggressive"):format(state))
            end
        end, "aggressive_mode")
    self:CreateToggle(panel, L:Get("menu_defender"), L:Get("tooltip_defender"),
        AC.Settings.defender_mode or false,
        function(val)
            local ply = LocalPlayer()
            if IsValid(ply) then
                local state = val and L:Get("mode_on") or L:Get("mode_off")
                ply:ChatPrint("[" .. L:Get("ai_prefix") .. "] " .. L:Get("mode_defender"):format(state))
            end
        end, "defender_mode")
    self:CreateToggle(panel, L:Get("menu_medic"), L:Get("tooltip_medic"),
        AC.Settings.medic_mode or false,
        function(val)
            local ply = LocalPlayer()
            if IsValid(ply) then
                local state = val and L:Get("mode_on") or L:Get("mode_off")
                ply:ChatPrint("[" .. L:Get("ai_prefix") .. "] " .. L:Get("mode_medic"):format(state))
            end
        end, "medic_mode")
end
function PANEL:BuildAppearanceTab()
    local scroll = vgui.Create("DScrollPanel")
    self.Sheet:AddSheet(L:Get("menu_appearance"), scroll, "icon16/palette.png")
    local panel = vgui.Create("DPanel", scroll)
    panel:Dock(TOP)
    panel:SetTall(1200)
    panel.Paint = function() end
    self:CreateSection(panel, L:Get("menu_appearance_prefix"))
    self:CreateTextEntry(panel, L:Get("menu_prefix_text"), L:Get("tooltip_prefix_text"),
        AC.Settings.prefix_text or "[AI]",
        function(text)
            local ply = LocalPlayer()
            if not IsValid(ply) then return end
            text = string.Trim(text)
            if text == "" then
                ply:ChatPrint("[AI] " .. L:Get("settings_prefix_empty"))
                return
            end
            text = string.gsub(text, "[<>\"'&]", "")
            if AC.Settings then AC.Settings.prefix_text = text end
            SendSettingToServer("prefix_text", text)
            if SetPlayerSetting then
                SetPlayerSetting(ply, "prefix_text", text)
            end
        end, "prefix_text")
    self:CreateSection(panel, L:Get("menu_personalization"))
    self:CreateToggle(panel, L:Get("menu_show_sender_name"), L:Get("tooltip_show_sender"),
        AC.Settings.show_sender_name or true,
        function(val)
            AC.Settings.show_sender_name = val
            SendSettingToServer("show_sender_name", val)
            if SetPlayerSetting then
                SetPlayerSetting(LocalPlayer(), "show_sender_name", val)
            end
            local state = val and L:Get("mode_on") or L:Get("mode_off")
            LocalPlayer():ChatPrint("[" .. L:Get("ai_prefix") .. "] " .. L:Get("menu_show_sender_name") .. ": " .. state)
        end, "show_sender_name")
    local examplePanel = vgui.Create("DPanel", panel)
    examplePanel:Dock(TOP)
    examplePanel:DockMargin(8, 2, 8, 4)
    examplePanel:SetTall(28)
    examplePanel.Paint = function(s, w, h)
        surface.SetDrawColor(30, 30, 40, 150)
        surface.DrawRect(0, 0, w, h)
        local showName = AC.Settings.show_sender_name
        if showName == nil then showName = true end
        local prefix = AC.Settings.prefix_text or "[AI]"
        local cleanPrefix = prefix
        cleanPrefix = string.gsub(cleanPrefix, "^%[", "")
        cleanPrefix = string.gsub(cleanPrefix, "%]$", "")
        if cleanPrefix == "" then cleanPrefix = "AI" end
        local exampleText
        if showName then
            exampleText = L:Get("example_with_name"):format(cleanPrefix)
        else
            exampleText = L:Get("example_without_name"):format(cleanPrefix)
        end
        draw.SimpleText(L:Get("menu_example"), "DermaDefault", 8, h/2, Color(150, 150, 150), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(exampleText, "DermaDefault", 70, h/2, Color(100, 200, 255), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    examplePanel.Think = function(s)
        s:InvalidateLayout()
    end
    self:CreateSection(panel, L:Get("menu_prefix_color"))
    self:CreateTextEntry(panel, L:Get("menu_red"), L:Get("tooltip_color"),
        tostring(AC.Settings.prefix_r or 255),
        function(text)
            local ply = LocalPlayer()
            if IsValid(ply) then
                local val = tonumber(text)
                if val and val >= 0 and val <= 255 then
                    if AC.Settings then AC.Settings.prefix_r = val end
                    if SetPlayerSetting then SetPlayerSetting(ply, "prefix_r", val) end
                end
            end
        end, "prefix_r")
    self:CreateTextEntry(panel, L:Get("menu_green"), L:Get("tooltip_color"),
        tostring(AC.Settings.prefix_g or 200),
        function(text)
            local ply = LocalPlayer()
            if IsValid(ply) then
                local val = tonumber(text)
                if val and val >= 0 and val <= 255 then
                    if AC.Settings then AC.Settings.prefix_g = val end
                    if SetPlayerSetting then SetPlayerSetting(ply, "prefix_g", val) end
                end
            end
        end, "prefix_g")
    self:CreateTextEntry(panel, L:Get("menu_blue"), L:Get("tooltip_color"),
        tostring(AC.Settings.prefix_b or 0),
        function(text)
            local ply = LocalPlayer()
            if IsValid(ply) then
                local val = tonumber(text)
                if val and val >= 0 and val <= 255 then
                    if AC.Settings then AC.Settings.prefix_b = val end
                    if SetPlayerSetting then SetPlayerSetting(ply, "prefix_b", val) end
                end
            end
        end, "prefix_b")
    self:CreateToggle(panel, L:Get("menu_rainbow_prefix"), L:Get("tooltip_rainbow"),
        AC.Settings.prefix_rainbow or false,
        function(val)
            local ply = LocalPlayer()
            if IsValid(ply) then
                if AC.Settings then AC.Settings.prefix_rainbow = val end
                if SetPlayerSetting then SetPlayerSetting(ply, "prefix_rainbow", val) end
                local state = val and L:Get("mode_on") or L:Get("mode_off")
                ply:ChatPrint("[" .. L:Get("ai_prefix") .. "] " .. L:Get("settings_rainbow"):format(state))
            end
        end, "prefix_rainbow")
    self:CreateSection(panel, L:Get("menu_preview"))
    local preview = vgui.Create("DPanel", panel)
    preview:Dock(TOP)
    preview:DockMargin(8, 4, 8, 4)
    preview:SetTall(40)
    preview.Paint = function(s, w, h)
        local settings = AC.Settings
        if not settings then return end
        local prefix = settings.prefix_text or "[AI]"
        local r, g, b = settings.prefix_r or 255, settings.prefix_g or 200, settings.prefix_b or 0
        if settings.prefix_rainbow then
            local col = HSVToColor((CurTime() * 60) % 360, 1, 1)
            r, g, b = col.r, col.g, col.b
        end
        local cleanPrefix = prefix
        cleanPrefix = string.gsub(cleanPrefix, "^%[", "")
        cleanPrefix = string.gsub(cleanPrefix, "%]$", "")
        if cleanPrefix == "" then cleanPrefix = "AI" end
        local showName = settings.show_sender_name
        if showName == nil then showName = true end
        local displayText
        if showName then
            displayText = L:Get("preview_with_name"):format(cleanPrefix)
        else
            displayText = L:Get("preview_without_name"):format(cleanPrefix)
        end
        draw.SimpleText(displayText, "DermaDefaultBold", w/2, h/2, Color(r, g, b), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    preview.Think = function(s)
        s:InvalidateLayout()
    end
    self:CreateSection(panel, L:Get("menu_quick_colors"))
    local colors = {
        {L:Get("menu_quick_standard"), "255 200 0"},
        {L:Get("color_white"), "255 255 255"},
        {L:Get("color_black"), "30 30 30"},
        {L:Get("color_gray"), "150 150 150"},
        {L:Get("color_red"), "255 50 50"},
        {L:Get("color_dark_red"), "180 0 0"},
        {L:Get("color_orange"), "255 150 0"},
        {L:Get("color_yellow"), "255 255 0"},
        {L:Get("color_lime"), "150 255 50"},
        {L:Get("color_green"), "50 255 50"},
        {L:Get("color_dark_green"), "0 150 0"},
        {L:Get("color_cyan"), "0 255 255"},
        {L:Get("color_light_blue"), "50 200 255"},
        {L:Get("color_blue"), "50 100 255"},
        {L:Get("color_dark_blue"), "0 50 180"},
        {L:Get("color_purple"), "150 50 255"},
        {L:Get("color_pink"), "255 100 200"},
        {L:Get("color_magenta"), "255 0 255"},
        {L:Get("color_brown"), "150 100 50"},
        {L:Get("color_chat"), "255 255 178"},
        {L:Get("color_admin_red"), "255 0 0"},
        {L:Get("color_gold"), "255 215 0"},
        {L:Get("color_silver"), "192 192 192"},
    }
    for _, col in ipairs(colors) do
        self:CreateButton(panel, col[1], L:Get("tooltip_set_color"):format(col[2]), function()
            local rgb = string.Explode(" ", col[2])
            local ply = LocalPlayer()
            if IsValid(ply) then
                local r, g, b = tonumber(rgb[1]), tonumber(rgb[2]), tonumber(rgb[3])
                if AC.Settings then
                    AC.Settings.prefix_r = r
                    AC.Settings.prefix_g = g
                    AC.Settings.prefix_b = b
                end
                SendSettingToServer("prefix_r", r)
                SendSettingToServer("prefix_g", g)
                SendSettingToServer("prefix_b", b)
                if SetPlayerSetting then
                    SetPlayerSetting(ply, "prefix_r", r)
                    SetPlayerSetting(ply, "prefix_g", g)
                    SetPlayerSetting(ply, "prefix_b", b)
                end
                self:RefreshValues()
            end
        end)
    end
end
function PANEL:BuildInfoTab()
    local scroll = vgui.Create("DScrollPanel")
    self.Sheet:AddSheet(L:Get("menu_info"), scroll, "icon16/information.png")
    local panel = vgui.Create("DPanel", scroll)
    panel:Dock(TOP)
    panel:SetTall(650)
    panel.Paint = function() end
    if not IS_SOLO then
        self:CreateSection(panel, L:Get("menu_status"))
        self.BotStatusLabel = vgui.Create("DLabel", panel)
        self.BotStatusLabel:Dock(TOP)
        self.BotStatusLabel:DockMargin(8, 4, 8, 8)
        self.BotStatusLabel:SetTall(150)
        self.BotStatusLabel:SetWrap(true)
        self.BotStatusLabel:SetTextColor(Color(200, 200, 200))
        self.BotStatusLabel:SetFont("DermaDefault")
        self:RefreshBotStatus()
        self:CreateButton(panel, L:Get("menu_show_status"), L:Get("tooltip_refresh_status"),
            function()
                self:RefreshBotStatus()
            end)
    end
    self:CreateSection(panel, L:Get("menu_about"))
    local about = vgui.Create("DLabel", panel)
    about:SetText(L:Get("menu_about_text"))
    about:Dock(TOP)
    about:DockMargin(8, 4, 8, 4)
    about:SetTall(350)
    about:SetWrap(true)
    about:SetTextColor(Color(0, 191, 255))
    about:SetFont("DermaDefault")
end
function PANEL:BuildPromptTab()
    local scroll = vgui.Create("DScrollPanel")
    self.Sheet:AddSheet(L:Get("menu_prompt") or "Prompt", scroll, "icon16/script_edit.png")
    local panel = vgui.Create("DPanel", scroll)
    panel:Dock(TOP)
    panel:SetTall(700)
    panel.Paint = function() end
    self:CreateSection(panel, L:Get("menu_prompt_custom") or "Custom Prompt")
    self:CreateToggle(panel, L:Get("menu_prompt_enabled") or "Use custom prompt",
        L:Get("tooltip_prompt_enabled") or "Enable/disable custom system prompt",
        AC.Settings.custom_prompt_enabled or false,
        function(val)
            AC.Settings.custom_prompt_enabled = val
            SendSettingToServer("custom_prompt_enabled", val)
            if SetPlayerSetting then
                SetPlayerSetting(LocalPlayer(), "custom_prompt_enabled", val)
            end
            local state = val and L:Get("mode_on") or L:Get("mode_off")
            LocalPlayer():ChatPrint("[" .. L:Get("ai_prefix") .. "] " .. (L:Get("prompt_enabled") or "Custom prompt") .. ": " .. state)
        end, "custom_prompt_enabled")
    local sysInfo = vgui.Create("DLabel", panel)
    sysInfo:SetText(L:Get("menu_prompt_system_info") or "When custom prompt is disabled, the standard system prompt is used.")
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
    self:CreateSection(panel, L:Get("menu_prompt_editor") or "Prompt Editor")
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
    promptEntry:SetText(AC.Settings.custom_prompt_text or "")
    promptEntry:SetFont("DermaDefault")
    promptEntry:SetTextColor(Color(220, 220, 220))
    promptEntry:SetPaintBackground(false)
    promptEntry:SetUpdateOnType(true)
    promptEntry._lastText = AC.Settings.custom_prompt_text or ""
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
        charCount:SetText((L:Get("prompt_chars") or "Characters: ") .. count .. " / " .. maxLen)
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
            AC.Settings.custom_prompt_text = text
            SendSettingToServer("custom_prompt_text", text)
            if SetPlayerSetting then
                SetPlayerSetting(LocalPlayer(), "custom_prompt_text", text)
            end
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
    saveBtn:SetText(L:Get("prompt_save") or "Save")
    saveBtn.DoClick = function()
        local text = promptEntry:GetText()
        if #text > 8000 then
            text = string.sub(text, 1, 8000)
            promptEntry:SetText(text)
        end
        AC.Settings.custom_prompt_text = text
        SendSettingToServer("custom_prompt_text", text)
        if SetPlayerSetting then
            SetPlayerSetting(LocalPlayer(), "custom_prompt_text", text)
        end
        promptEntry._lastText = text
        UpdateCharCount()
        LocalPlayer():ChatPrint("[" .. L:Get("ai_prefix") .. "] " .. (L:Get("prompt_saved") or "Prompt saved"))
    end
    local resetBtn = vgui.Create("DButton", btnPanel)
    resetBtn:Dock(LEFT)
    resetBtn:DockMargin(8, 0, 0, 0)
    resetBtn:SetWide(120)
    resetBtn:SetText(L:Get("prompt_reset") or "Reset")
    resetBtn.DoClick = function()
        Derma_Query(
            L:Get("dialog_reset_prompt") or "Reset custom prompt? The standard system prompt will be used.",
            L:Get("dialog_replace_title") or "Confirm",
            L:Get("dialog_yes") or "Yes",
            function()
                promptEntry:SetText("")
                promptEntry._lastText = ""
                AC.Settings.custom_prompt_text = ""
                SendSettingToServer("custom_prompt_text", "")
                if SetPlayerSetting then
                    SetPlayerSetting(LocalPlayer(), "custom_prompt_text", "")
                end
                UpdateCharCount()
                LocalPlayer():ChatPrint("[" .. L:Get("ai_prefix") .. "] " .. (L:Get("prompt_reset_done") or "Prompt reset"))
            end,
            L:Get("dialog_no") or "No",
            function() end
        )
    end
    self.InputFields["custom_prompt_text"] = promptEntry
    UpdateCharCount()
    if LocalPlayer():IsAdmin() then
        self:CreateSection(panel, L:Get("menu_prompt_admin") or "Admin Settings")
        self:CreateToggle(panel, L:Get("menu_prompt_allow_custom") or "Allow custom prompts for players",
            L:Get("tooltip_prompt_allow_custom") or "Enable/disable custom prompts for regular players",
            AC.Settings.allow_custom_prompts ~= false,
            function(val)
                AC.Settings.allow_custom_prompts = val
                SendSettingToServer("allow_custom_prompts", val)
                if SetPlayerSetting then
                    SetPlayerSetting(LocalPlayer(), "allow_custom_prompts", val)
                end
                local state = val and L:Get("mode_on") or L:Get("mode_off")
                LocalPlayer():ChatPrint("[" .. L:Get("ai_prefix") .. "] " .. (L:Get("prompt_allow_custom") or "Custom prompts for players") .. ": " .. state)
            end, "allow_custom_prompts")
        local adminInfo = vgui.Create("DLabel", panel)
        adminInfo:SetText(L:Get("menu_prompt_admin_info") or "When disabled, regular players cannot change their prompt. Admins can always change it.")
        adminInfo:Dock(TOP)
        adminInfo:DockMargin(8, 4, 8, 8)
        adminInfo:SetTall(50)
        adminInfo:SetWrap(true)
        adminInfo:SetTextColor(Color(0, 191, 255))
        adminInfo:SetFont("DermaDefault")
    end
    local warn = vgui.Create("DLabel", panel)
    warn:SetText(L:Get("menu_prompt_warn") or "Long prompts may increase response time and token usage. Recommended length: up to 2000 characters.")
    warn:Dock(TOP)
    warn:DockMargin(8, 8, 8, 4)
    warn:SetTall(40)
    warn:SetWrap(true)
    warn:SetTextColor(Color(255, 200, 100))
    warn:SetFont("DermaDefaultBold")
end
function PANEL:BuildWorkflowTab()
    local scroll = vgui.Create("DScrollPanel")
    self.Sheet:AddSheet(L:Get("menu_workflow") or "Workflow", scroll, "icon16/bricks.png")
    local panel = vgui.Create("DPanel", scroll)
    panel:Dock(TOP)
    panel:SetTall(600)
    panel.Paint = function() end
    if not LocalPlayer():IsAdmin() then
        local noAccess = vgui.Create("DLabel", panel)
        noAccess:SetText(L:Get("menu_workflow_no_access") or "Admin Only")
        noAccess:Dock(TOP)
        noAccess:DockMargin(8, 20, 8, 4)
        noAccess:SetTall(30)
        noAccess:SetTextColor(Color(255, 100, 100))
        noAccess:SetFont("DermaDefaultBold")
        noAccess:SetContentAlignment(5)
        local info = vgui.Create("DLabel", panel)
        info:SetText(L:Get("menu_workflow_admin_only") or "Workflow management is only available to server admins.")
        info:Dock(TOP)
        info:DockMargin(8, 4, 8, 4)
        info:SetTall(30)
        info:SetTextColor(Color(0, 191, 255))
        info:SetFont("DermaDefault")
        info:SetContentAlignment(5)
        return
    end
    self:CreateSection(panel, L:Get("menu_workflow_manage") or "Workflow Management")
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
        local settings = AI_SETTINGS or AC.Settings or {}
        local enabled = settings.tts_workflow_enabled or false
        local filename = settings.tts_workflow_filename or (L:Get("workflow_none") or "Not loaded")
        local statusText = enabled and (L:Get("workflow_status_on") or "ON") or (L:Get("workflow_status_off") or "OFF")
        local statusColor = enabled and Color(100, 255, 100) or Color(255, 100, 100)
        if s._lastEnabled ~= enabled or s._lastFilename ~= filename then
            s._lastEnabled = enabled
            s._lastFilename = filename
        end
        draw.SimpleText(
            (L:Get("workflow_current") or "Current workflow:") .. " " .. filename,
            "DermaDefault",
            12, 12,
            Color(200, 200, 200)
        )
        draw.SimpleText(
            (L:Get("workflow_status") or "Status:") .. " " .. statusText,
            "DermaDefault",
            12, 34,
            statusColor
        )
        draw.SimpleText(
            (L:Get("workflow_provider") or "Provider:") .. " ComfyUI (Local TTS)",
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
    self:CreateButton(panel, L:Get("menu_workflow_load") or "Load workflow from file",
        L:Get("tooltip_workflow_load") or "Load JSON workflow from file (data/)",
        function()
            local frame = vgui.Create("DFrame")
            frame:SetTitle(L:Get("workflow_load_title") or "Load Workflow")
            frame:SetSize(400, 150)
            frame:Center()
            frame:MakePopup()
            frame:SetDraggable(true)
            frame:ShowCloseButton(true)
            local lbl = vgui.Create("DLabel", frame)
            lbl:SetText(L:Get("workflow_load_path") or "File path (relative to data/):")
            lbl:SetPos(10, 35)
            lbl:SetWide(380)
            lbl:SetTextColor(Color(220, 220, 220))
            local entry = vgui.Create("DTextEntry", frame)
            entry:SetPos(10, 60)
            entry:SetSize(380, 24)
            entry:SetText("ai_workflow.json")
            entry:SetTextColor(Color(220, 220, 220))
            local loadBtn = vgui.Create("DButton", frame)
            loadBtn:SetText(L:Get("dialog_yes") or "Load")
            loadBtn:SetPos(10, 100)
            loadBtn:SetSize(180, 28)
            loadBtn.DoClick = function()
                local path = entry:GetText()
                if path and path ~= "" then
                    LocalPlayer():ConCommand('ai_tts_workflow_load "' .. path .. '"')
                    timer.Simple(0.3, function()
                        if IsValid(self) and IsValid(self.WorkflowStatusPanel) then
                            self.WorkflowStatusPanel:UpdateStatus()
                        end
                    end)
                end
                frame:Close()
            end
            local cancelBtn = vgui.Create("DButton", frame)
            cancelBtn:SetText(L:Get("dialog_no") or "Cancel")
            cancelBtn:SetPos(210, 100)
            cancelBtn:SetSize(180, 28)
            cancelBtn.DoClick = function()
                frame:Close()
            end
        end)
    self:CreateButton(panel, L:Get("menu_workflow_toggle") or "Toggle workflow",
        L:Get("tooltip_workflow_toggle") or "Enable/disable custom workflow",
        function()
            LocalPlayer():ConCommand("ai_tts_workflow_toggle")
            timer.Simple(0.3, function()
                if IsValid(self) then
                    self:RefreshValues()
                    if IsValid(self.WorkflowStatusPanel) then
                        self.WorkflowStatusPanel:UpdateStatus()
                    end
                end
            end)
        end)
    self:CreateButton(panel, L:Get("menu_workflow_reset") or "Reset to default",
        L:Get("tooltip_workflow_reset") or "Reset workflow to default OmniVoice",
        function()
            Derma_Query(
                L:Get("dialog_reset_workflow") or "Reset workflow to default?",
                L:Get("dialog_replace_title") or "Confirm",
                L:Get("dialog_yes") or "Yes",
                function()
                    LocalPlayer():ConCommand("ai_tts_workflow_reset")
                    timer.Simple(0.3, function()
                        if IsValid(self) then
                            self:RefreshValues()
                            if IsValid(self.WorkflowStatusPanel) then
                                self.WorkflowStatusPanel:UpdateStatus()
                            end
                        end
                    end)
                end,
                L:Get("dialog_no") or "No",
                function() end
            )
        end)
    self:CreateButton(panel, L:Get("menu_workflow_status") or "Show status",
        L:Get("tooltip_workflow_status") or "Show current workflow status in chat",
        function()
            LocalPlayer():ConCommand("ai_tts_workflow_status")
        end)
    self:CreateSection(panel, L:Get("menu_workflow_info") or "Information")
    local infoText = vgui.Create("DLabel", panel)
    infoText:SetText(L:Get("menu_workflow_info_text") or [[
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
function OpenAICompanionMenu()
    if IsValid(_G.AICompanionMenuPanel) then _G.AICompanionMenuPanel:Remove() end
    _G.AICompanionMenuPanel = vgui.Create("AICompanionMenu")
end
hook.Add("PopulateToolMenu", "AICompanion_ToolMenu", function()
    local SafeL = L or _G.L or { Get = function(s,k) return k end }
    spawnmenu.AddToolMenuOption("Utilities", "AI Companion", "AICompanionSettings",
        SafeL:Get("menu_title"), "", "", function(panel)
        panel:ClearControls()
        local btn = panel:Button(SafeL:Get("menu_title"))
        btn.DoClick = function() OpenAICompanionMenu() end
        panel:Help(SafeL:Get("toolmenu_help"))
    end)
end)
concommand.Add("ai_companion_menu", function(ply, cmd, args)
    if CLIENT then
        OpenAICompanionMenu()
    end
end)
net.Receive("AI_TTS_Global_Status", function()
    local status = net.ReadBool()
    _G.AI_Companion_TTS_Enabled = status
    if IsValid(_G.AICompanionMenuPanel) then _G.AICompanionMenuPanel:RefreshValues() end
    local SafeL = L or _G.L or { Get = function(s,k) return k end }
    chat.AddText(Color(100, 200, 255), "[AI] TTS " .. (status and SafeL:Get("mode_on") or SafeL:Get("mode_off")) .. " " .. SafeL:Get("tts_global_status"))
end)
end
MsgC(Color(100, 200, 255), "[AI Menu] " .. (L:Get("console_menu_loaded") or "Loaded") .. "\n")