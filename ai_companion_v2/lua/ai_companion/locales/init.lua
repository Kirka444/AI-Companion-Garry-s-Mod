if AI_LOCALES_LOADED then return end
AI_LOCALES_LOADED = true
include("ai_companion/locales/languages.lua")
if SERVER then
    util.AddNetworkString("AI_Locale_Sync")
end
local LOCALES = {}
local CURRENT_LANG = "ru"
local AVAILABLE_LANGS = {
    "ru", "en", "de", "es", "fr", "it", "ja", "ko", "pl", "pt", "uk", "zh", "tr", "cs", "sv", "nl"
}
local function LoadLocale(lang)
    local path = "ai_companion/locales/" .. lang .. ".lua"
    local ok, data = pcall(include, path)
    if ok and data and type(data) == "table" then
        LOCALES[lang] = data
        return true
    end
    return false
end
local function LoadAllLocales()
    for _, lang in ipairs(AVAILABLE_LANGS) do
        local loaded = LoadLocale(lang)
        if loaded then
            print("[AI Locale] Loaded: " .. lang)
        else
            print("[AI Locale] Failed to load: " .. lang .. " (skipping)")
        end
    end
    if next(LOCALES) == nil then
        print("[AI Locale] No languages loaded! Creating fallback...")
        LOCALES["ru"] = {
            ["ai_prefix"] = "[AI]",
            ["menu_title"] = "AI Companion",
        }
    end
end
local function GetLanguageName(langCode)
    if LANGUAGES and LANGUAGES[langCode] then
        return LANGUAGES[langCode]
    end
    return langCode
end
_L = {
    _lang = "ru",
    _strings = {},
    _callbacks = {},
    SetLang = function(self, lang)
        if not LOCALES[lang] then
            return false
        end
        self._lang = lang
        self._strings = LOCALES[lang]
        CURRENT_LANG = lang
        if AI_SETTINGS then
            AI_SETTINGS.locale = lang
            if AI_SaveSettings then
                AI_SaveSettings()
            end
        end
        if SERVER and not game.SinglePlayer() then
            if net and net.Start then
                net.Start("AI_Locale_Sync")
                net.WriteString(lang)
                net.Broadcast()
            end
        end
        for _, cb in ipairs(self._callbacks) do
            pcall(cb, lang)
        end
        return true
    end,
    Get = function(self, key, ...)
        if key == "ai_prefix" then
            local prefix = (AI_SETTINGS and AI_SETTINGS.prefix_text) or "[AI]"
            return prefix
        end
        if string.sub(key, 1, 5) == "lang_" then
            local langCode = string.sub(key, 6)
            return GetLanguageName(langCode)
        end
        local str = self._strings[key] or key
        if select("#", ...) > 0 then
            return string.format(str, ...)
        end
        return str
    end,
    GetLang = function(self)
        return self._lang
    end,
    GetAvailable = function(self)
        local result = {}
        for lang, _ in pairs(LOCALES) do
            table.insert(result, lang)
        end
        return result
    end,
    GetLanguageName = GetLanguageName,
    OnChange = function(self, cb)
        table.insert(self._callbacks, cb)
    end
}
LoadAllLocales()
local defaultLang = (AI_SETTINGS and AI_SETTINGS.locale) or "ru"
if LOCALES[defaultLang] then
    _L:SetLang(defaultLang)
else
    local available = _L:GetAvailable()
    if #available > 0 then
        _L:SetLang(available[1])
    else
        _L._strings = {
            ["ai_prefix"] = "[AI]",
            ["menu_title"] = "AI Companion",
        }
        _L._lang = "ru"
    end
end
if SERVER then
    net.Receive("AI_Locale_Sync", function(len, ply)
        if not IsValid(ply) then return end
        local lang = net.ReadString()
        if _L:SetLang(lang) then
            if SetPlayerSetting then
                SetPlayerSetting(ply, "locale", lang)
            end
            net.Start("AI_Locale_Sync")
            net.WriteString(lang)
            net.Send(ply)
        end
    end)
end
if CLIENT then
    net.Receive("AI_Locale_Sync", function()
        local lang = net.ReadString()
        if lang then
            _L:SetLang(lang)
            if IsValid(_G.AICompanionMenuPanel) then
                _G.AICompanionMenuPanel:RefreshAllTabs()
            end
        end
    end)
end
_G.AI_L = _L
if not _G.L then
    _G.L = _G.AI_L
else
    if type(_G.L) == "table" then
        for k, v in pairs(_L) do
            if type(v) == "function" and not _G.L[k] then
                _G.L[k] = v
            end
        end
    end
end
if _G._L ~= _G.L then
    _G._L = _G.L
end
_G.L._is_ai_companion = true
print("[AI Locale] Loaded, current language: " .. _L:GetLang())
print("[AI Locale] Available languages: " .. table.concat(_L:GetAvailable(), ", "))