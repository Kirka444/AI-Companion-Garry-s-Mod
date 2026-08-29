
if AI_LOCALES_INIT_LOADED then return end
AI_LOCALES_INIT_LOADED = true

include("ai_companion/locales/languages.lua")

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

function Locale:init()
    if self._initialized then return end

    local locator = _G.AI_GetLocator and _G.AI_GetLocator()
    if locator and locator:has("state") then
        local state = locator:get("state")
        local savedLang = state:getSetting("locale")
        if savedLang then
            self._lang = savedLang
        end
    end

    self:SetLang(self._lang)
    self._initialized = true

    if SERVER then
        print("[AI Locale] Инициализирован, язык: " .. self._lang)
    end
end

function Locale:SetLang(lang)

    if not LANGUAGES or not LANGUAGES[lang] then
        print("[AI Locale] ⚠️ Язык '" .. tostring(lang) .. "' не найден в LANGUAGES, используем ru")
        lang = "ru"
    end

    local path = "ai_companion/locales/" .. lang .. ".lua"

    if SERVER then
        AddCSLuaFile(path)
    end

    local content = file.Read(path, "LUA")
    if not content then
        print("[AI Locale] ❌ Файл не найден: " .. path)
        return false
    end

    local func = CompileString(content, path, false)
    if type(func) == "string" then
        print("[AI Locale] ❌ Ошибка компиляции " .. lang .. ": " .. func)
        return false
    end

    local ok, data = pcall(func)
    if not ok then
        print("[AI Locale] ❌ Ошибка выполнения " .. lang .. ": " .. tostring(data))
        return false
    end

    if not data or type(data) ~= "table" then
        print("[AI Locale] ❌ Файл " .. lang .. " не вернул таблицу (тип: " .. type(data) .. ")")
        return false
    end

    self._strings = data
    self._lang = lang

    for _, cb in ipairs(self._callbacks) do
        pcall(cb, lang)
    end

    if SERVER or (CLIENT and self._initialized) then
        print("[AI Locale] ✅ Язык загружен: " .. lang .. " (" .. table.Count(data) .. " строк)")
    end

    return true
end

function Locale:Get(key, ...)
    local str = self._strings[key]
    if str == nil then

        str = key
    end
    if select("#", ...) > 0 then
        return string.format(str, ...)
    end
    return str
end

function Locale:GetLang()
    return self._lang
end

function Locale:GetAvailable()
    local result = {}
    if LANGUAGES then
        for lang, _ in pairs(LANGUAGES) do
            table.insert(result, lang)
        end
    end
    return result
end

function Locale:OnChange(cb)
    table.insert(self._callbacks, cb)
end

return Locale
