
local ok, locator = pcall(include, "ai_companion/services/servicelocator.lua")
if not ok then
    ErrorNoHalt("[AI Companion] НЕ УДАЛОСЬ ЗАГРУЗИТЬ ЛОКАТОР: " .. tostring(locator) .. "\n")
    return
end

_G.AI_GetLocator = function()
    local reg = debug.getregistry()
    local loc = reg["__AI_COMPANION_LOCATOR_v2"]
    if not loc then
        error("[AI Companion] Локатор не найден на сервере!")
    end
    return loc
end

local ok2, err = pcall(include, "ai_companion/init.lua")
if not ok2 then
    ErrorNoHalt("[AI Companion] Ошибка загрузки серверного init: " .. tostring(err) .. "\n")
    return
end

timer.Simple(0.5, function()
    local loc = _G.AI_GetLocator()
    if not loc then return end

    local commands = loc:get("commands")
    if commands then
        print("[AI Companion] Команды зарегистрированы!")
    else
        print("[AI Companion] НЕ УДАЛОСЬ ЗАГРУЗИТЬ КОМАНДЫ!")
    end
end)

print("[AI Companion] Серверная часть загружена")
