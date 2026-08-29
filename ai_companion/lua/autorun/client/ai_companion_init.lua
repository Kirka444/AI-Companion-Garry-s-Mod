
print("[AI Companion] Клиентский init начал загрузку...")

local function tryInit()

    local reg = debug.getregistry()
    local locator = reg["__AI_COMPANION_LOCATOR_v2"]

    if not locator then

        print("[AI Companion] Клиент: локатор не найден, создаю...")
        local ok, err = pcall(include, "ai_companion/services/servicelocator.lua")
        if not ok then
            ErrorNoHalt("[AI Companion] Клиент: не удалось загрузить локатор: " .. tostring(err) .. "\n")
            timer.Simple(0.5, tryInit)
            return
        end

        locator = reg["__AI_COMPANION_LOCATOR_v2"]
        if not locator then
            timer.Simple(0.5, tryInit)
            return
        end
    end

    _G.AI_GetLocator = function()
        local reg = debug.getregistry()
        local loc = reg["__AI_COMPANION_LOCATOR_v2"]
        if not loc then
            error("[AI Companion] Клиент: локатор не найден!")
        end
        return loc
    end

    local ok, err = pcall(include, "ai_companion/init.lua")
    if not ok then
        ErrorNoHalt("[AI Companion] Клиент: ошибка загрузки init: " .. tostring(err) .. "\n")
        return
    end

    print("[AI Companion] Клиентская часть загружена!")
    print("[AI Companion] Локатор доступен через _G.AI_GetLocator()")
end

timer.Simple(0.1, tryInit)
