-- Localization loader and runtime language manager.

if AI_LOCALES_INIT_LOADED then return end
AI_LOCALES_INIT_LOADED = true

include("ai_companion/locales/languages.lua")

if not AICompanion_LANGUAGES then
    AICompanion_LANGUAGES = { ru = true, en = true }
end

local Locale = {}

function Locale:new()
    local obj = {
        _lang = "ru",
        _strings = {},
        _callbacks = {},
        _initialized = false,
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function Locale:GetLocalized(key, ...)
    local str = self._strings[key]
    if str == nil then
        str = key
    end
    if select("#", ...) > 0 then
        local ok, result = pcall(string.format, str, ...)
        if ok then
            return result
        end
        return str
    end
    return str
end

function Locale:init()
    if self._initialized then return end

    local locator = AICompanion and AICompanion.GetLocator and AICompanion.GetLocator()
    if locator and locator:has("state") then
        local state = locator:get("state")

        if CLIENT then
            local ply = LocalPlayer()
            if IsValid(ply) then
                local steamID = ply:SteamID64()
                local personalLang = state:getPlayerSetting(steamID, "Locale")
                if personalLang then
                    self._lang = personalLang
                end
            end
        end

        if not self._lang or self._lang == "ru" then
            local globalLang = state:getSetting("Locale")
            if globalLang then
                self._lang = globalLang
            end
        end
    end

    self:SetLang(self._lang)
    self._initialized = true

    if SERVER then
        print("[AI Locale] " .. self:GetLocalized("locale_initialized") .. ": " .. self._lang)
    end
end

function Locale:SetLang(lang)
    if not AICompanion_LANGUAGES or not AICompanion_LANGUAGES[lang] then
        print("[AI Locale] " .. self:GetLocalized("locale_lang_not_found"):format(tostring(lang)))
        lang = "ru"
    end

    local path = "ai_companion/locales/" .. lang .. ".lua"

    if SERVER then
        AddCSLuaFile(path)
    end

    local content = file.Read(path, "LUA")
    if not content then
        print("[AI Locale] " .. self:GetLocalized("locale_file_not_found") .. ": " .. path)
        return false
    end

    local func = CompileString(content, path, false)
    if type(func) == "string" then
        print("[AI Locale] " .. self:GetLocalized("locale_compile_error") .. " " .. lang .. ": " .. func)
        return false
    end

    local ok, data = pcall(func)
    if not ok then
        print("[AI Locale] " .. self:GetLocalized("locale_exec_error") .. " " .. lang .. ": " .. tostring(data))
        return false
    end

    if not data or type(data) ~= "table" then
        print("[AI Locale] " .. self:GetLocalized("locale_not_table"):format(lang, type(data)))
        return false
    end

    self._strings = data
    self._lang = lang

    for _, cb in ipairs(self._callbacks) do
        pcall(cb, lang)
    end

    if SERVER or (CLIENT and self._initialized) then
        print("[AI Locale] " .. self:GetLocalized("locale_loaded_success"):format(lang, table.Count(data)))
    end

    return true
end

function Locale:Get(key, ...)
    local str = self._strings[key]
    if str == nil then
        str = key
    end
    if select("#", ...) > 0 then
        local ok, result = pcall(string.format, str, ...)
        if ok then
            return result
        end
        return str
    end
    return str
end

function Locale:GetLang()
    return self._lang
end

function Locale:GetAvailable()
    local result = {}
    if AICompanion_LANGUAGES then
        for lang, _ in pairs(AICompanion_LANGUAGES) do
            table.insert(result, lang)
        end
    end
    return result
end

function Locale:OnChange(cb)
    table.insert(self._callbacks, cb)
end

return Locale
